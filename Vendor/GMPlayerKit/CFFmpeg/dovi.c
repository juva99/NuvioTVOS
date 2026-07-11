#include "gmdovi.h"

#include <errno.h>
#include <limits.h>
#include <string.h>

#include <Libdovi/rpu_parser.h>
#include <libavutil/dovi_meta.h>
#include <libavutil/error.h>
#include <libavutil/intreadwrite.h>
#include <libavutil/mem.h>

#define GM_DOVI_PROFILE_7 7
#define GM_DOVI_PROFILE_81 8
#define GM_DOVI_RPU_NAL_TYPE 62
#define GM_DOVI_BLOCK_TYPE_DVCC UINT64_C(0x64766343)
#define GM_DOVI_BLOCK_TYPE_DVVC UINT64_C(0x64767643)

struct GMDoviConverter {
    int profile;
    int nal_length_size;
    AVDOVIDecoderConfigurationRecord config;
};

typedef struct GMBuffer {
    uint8_t *data;
    size_t size;
    size_t capacity;
} GMBuffer;

static const AVDOVIDecoderConfigurationRecord *dovi_config(const AVCodecParameters *codecpar) {
    const AVPacketSideData *side_data = av_packet_side_data_get(
        codecpar->coded_side_data, codecpar->nb_coded_side_data, AV_PKT_DATA_DOVI_CONF);
    return side_data && side_data->size >= 9
        ? (const AVDOVIDecoderConfigurationRecord *)side_data->data : NULL;
}

static int buffer_reserve(GMBuffer *buffer, size_t additional) {
    if (additional > SIZE_MAX - buffer->size) return AVERROR(EOVERFLOW);
    size_t required = buffer->size + additional;
    if (required <= buffer->capacity) return 0;
    size_t capacity = buffer->capacity ? buffer->capacity : 4096;
    while (capacity < required) {
        if (capacity > SIZE_MAX / 2) { capacity = required; break; }
        capacity *= 2;
    }
    uint8_t *data = av_realloc(buffer->data, capacity);
    if (!data) return AVERROR(ENOMEM);
    buffer->data = data;
    buffer->capacity = capacity;
    return 0;
}

static int buffer_append(GMBuffer *buffer, const uint8_t *data, size_t size) {
    int ret = buffer_reserve(buffer, size);
    if (ret < 0) return ret;
    memcpy(buffer->data + buffer->size, data, size);
    buffer->size += size;
    return 0;
}

static int buffer_append_length(GMBuffer *buffer, size_t size, int length_size) {
    if (length_size < 1 || length_size > 4 || size > UINT32_MAX) return AVERROR_INVALIDDATA;
    if (length_size < 4 && size >= (1ULL << (length_size * 8))) return AVERROR_INVALIDDATA;
    uint8_t encoded[4];
    for (int i = length_size - 1; i >= 0; i--) {
        encoded[i] = (uint8_t)(size & 0xff);
        size >>= 8;
    }
    return buffer_append(buffer, encoded, (size_t)length_size);
}

static uint32_t read_length(const uint8_t *data, int length_size) {
    uint32_t value = 0;
    for (int i = 0; i < length_size; i++) value = (value << 8) | data[i];
    return value;
}

static int nal_type(const uint8_t *nal, size_t size) {
    return size >= 1 ? (nal[0] >> 1) & 0x3f : -1;
}

static int nal_layer_id(const uint8_t *nal, size_t size) {
    return size >= 2 ? ((nal[0] & 0x01) << 5) | ((nal[1] & 0xf8) >> 3) : 0;
}

static int convert_rpu(const uint8_t *nal, size_t size, GMBuffer *output) {
    DoviRpuOpaque *rpu = dovi_parse_unspec62_nalu(nal, size);
    if (!rpu || (dovi_rpu_get_error(rpu) && dovi_rpu_get_error(rpu)[0])) {
        if (rpu) dovi_rpu_free(rpu);
        return AVERROR_INVALIDDATA;
    }
    if (dovi_convert_rpu_with_mode(rpu, 2) < 0) {
        dovi_rpu_free(rpu);
        return AVERROR_INVALIDDATA;
    }
    const DoviData *converted = dovi_write_unspec62_nalu(rpu);
    if (!converted || !converted->data || converted->len < 2) {
        if (converted) dovi_data_free(converted);
        dovi_rpu_free(rpu);
        return AVERROR_INVALIDDATA;
    }
    int ret = buffer_reserve(output, converted->len);
    if (ret >= 0) {
        size_t offset = output->size;
        memcpy(output->data + offset, converted->data, converted->len);
        output->data[offset] &= 0xfe;
        output->data[offset + 1] &= 0x07;
        output->size += converted->len;
    }
    dovi_data_free(converted);
    dovi_rpu_free(rpu);
    return ret;
}

static int append_converted_rpu(GMBuffer *output, const uint8_t *nal, size_t size, int length_size) {
    GMBuffer converted = {0};
    int ret = convert_rpu(nal, size, &converted);
    if (ret >= 0) ret = buffer_append_length(output, converted.size, length_size);
    if (ret >= 0) ret = buffer_append(output, converted.data, converted.size);
    av_free(converted.data);
    return ret;
}

static int rewrite_length_prefixed(GMDoviConverter *converter, AVPacket *packet,
                                   const uint8_t *additional, size_t additional_size) {
    GMBuffer output = {0};
    size_t offset = 0;
    int changed = additional && additional_size;
    while (offset + (size_t)converter->nal_length_size <= (size_t)packet->size) {
        uint32_t size = read_length(packet->data + offset, converter->nal_length_size);
        offset += converter->nal_length_size;
        if (size > (size_t)packet->size - offset) { av_free(output.data); return AVERROR_INVALIDDATA; }
        const uint8_t *nal = packet->data + offset;
        int type = nal_type(nal, size);
        if (nal_layer_id(nal, size) > 0 && type != GM_DOVI_RPU_NAL_TYPE) {
            changed = 1;
        } else if (type == GM_DOVI_RPU_NAL_TYPE) {
            int ret = append_converted_rpu(&output, nal, size, converter->nal_length_size);
            if (ret < 0) { av_free(output.data); return ret; }
            changed = 1;
        } else {
            int ret = buffer_append_length(&output, size, converter->nal_length_size);
            if (ret >= 0) ret = buffer_append(&output, nal, size);
            if (ret < 0) { av_free(output.data); return ret; }
        }
        offset += size;
    }
    if (offset != (size_t)packet->size) { av_free(output.data); return AVERROR_INVALIDDATA; }
    if (additional && additional_size) {
        int ret = append_converted_rpu(&output, additional, additional_size, converter->nal_length_size);
        if (ret < 0) { av_free(output.data); return ret; }
    }
    if (!changed) { av_free(output.data); return 0; }
    if (output.size > INT_MAX) { av_free(output.data); return AVERROR(EOVERFLOW); }

    AVPacket *replacement = av_packet_alloc();
    if (!replacement) { av_free(output.data); return AVERROR(ENOMEM); }
    int ret = av_new_packet(replacement, (int)output.size);
    if (ret >= 0) ret = av_packet_copy_props(replacement, packet);
    if (ret >= 0) {
        memcpy(replacement->data, output.data, output.size);
        av_packet_side_data_remove(replacement->side_data, &replacement->side_data_elems,
                                   AV_PKT_DATA_MATROSKA_BLOCKADDITIONAL);
        av_packet_unref(packet);
        av_packet_move_ref(packet, replacement);
    }
    av_packet_free(&replacement);
    av_free(output.data);
    return ret;
}

static const uint8_t *block_additional(const AVPacket *packet, size_t *payload_size) {
    size_t size = 0;
    const uint8_t *data = av_packet_get_side_data(
        packet, AV_PKT_DATA_MATROSKA_BLOCKADDITIONAL, &size);
    if (!data || size <= 8) return NULL;
    uint64_t id = AV_RB64(data);
    if (id != 1 && id != GM_DOVI_BLOCK_TYPE_DVCC && id != GM_DOVI_BLOCK_TYPE_DVVC) return NULL;
    *payload_size = size - 8;
    return data + 8;
}

GMDoviConverter *gm_dovi_converter_create(const AVCodecParameters *codecpar) {
    if (!codecpar) return NULL;
    const AVDOVIDecoderConfigurationRecord *config = dovi_config(codecpar);
    GMDoviConverter *converter = av_mallocz(sizeof(*converter));
    if (!converter) return NULL;
    if (config) {
        converter->profile = config->dv_profile;
        converter->config = *config;
    }
    converter->nal_length_size = codecpar->extradata_size > 21 && codecpar->extradata[0] == 1
        ? (codecpar->extradata[21] & 3) + 1 : 4;
    return converter;
}

int gm_dovi_converter_profile(const GMDoviConverter *converter) {
    return converter ? converter->profile : 0;
}

int gm_dovi_converter_configure_output(const GMDoviConverter *converter, AVCodecParameters *codecpar) {
    if (!converter || !codecpar || converter->profile != GM_DOVI_PROFILE_7) return 0;
    size_t config_size = 0;
    AVDOVIDecoderConfigurationRecord *config = av_dovi_alloc(&config_size);
    if (!config) return AVERROR(ENOMEM);
    *config = converter->config;
    config->dv_profile = GM_DOVI_PROFILE_81;
    config->rpu_present_flag = 1;
    config->el_present_flag = 0;
    config->bl_present_flag = 1;
    config->dv_bl_signal_compatibility_id = 1;
    av_packet_side_data_remove(codecpar->coded_side_data, &codecpar->nb_coded_side_data,
                               AV_PKT_DATA_DOVI_CONF);
    if (!av_packet_side_data_add(&codecpar->coded_side_data, &codecpar->nb_coded_side_data,
                                 AV_PKT_DATA_DOVI_CONF, (uint8_t *)config, config_size, 0)) {
        av_free(config);
        return AVERROR(ENOMEM);
    }
    codecpar->codec_tag = MKTAG('d', 'v', 'h', '1');
    return 0;
}

int gm_dovi_converter_transform_packet(GMDoviConverter *converter, AVPacket *packet) {
    if (!converter || !packet || converter->profile != GM_DOVI_PROFILE_7) return 0;
    size_t additional_size = 0;
    const uint8_t *additional = block_additional(packet, &additional_size);
    return rewrite_length_prefixed(converter, packet, additional, additional_size);
}

void gm_dovi_converter_free(GMDoviConverter **converter) {
    if (!converter || !*converter) return;
    av_freep(converter);
}
