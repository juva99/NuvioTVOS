#include "gmdovi.h"

#include <libavutil/dovi_meta.h>
#include <libavutil/mem.h>
#include <Libdovi/rpu_parser.h>

struct GMDoviConverter {
    int profile;
};

GMDoviConverter *gm_dovi_converter_create(const AVCodecParameters *codecpar) {
    if (!codecpar) return NULL;

    GMDoviConverter *converter = av_mallocz(sizeof(*converter));
    if (!converter) return NULL;

    for (int i = 0; i < codecpar->nb_coded_side_data; i++) {
        const AVPacketSideData *side_data = &codecpar->coded_side_data[i];
        if (side_data->type == AV_PKT_DATA_DOVI_CONF && side_data->data && side_data->size >= 3) {
            converter->profile = side_data->data[2];
            break;
        }
    }
    return converter;
}

int gm_dovi_converter_profile(const GMDoviConverter *converter) {
    return converter ? converter->profile : 0;
}

int gm_dovi_converter_transform_packet(GMDoviConverter *converter, AVPacket *packet) {
    if (!converter || !packet || converter->profile != 7) return 0;

    // Keep libdovi linked through the shared MPVKit dependency while packet NAL
    // rewriting is completed. The converter must call this parser for each
    // UNSPEC62 RPU before converting mode 2 (Profile 8.1) and reinjecting it.
    DoviRpuOpaque *rpu = dovi_parse_unspec62_nalu(NULL, 0);
    if (rpu) dovi_rpu_free(rpu);
    return 0;
}

void gm_dovi_converter_free(GMDoviConverter **converter) {
    if (!converter || !*converter) return;
    av_freep(converter);
}
