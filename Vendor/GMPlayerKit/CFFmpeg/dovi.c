#include "gmdovi.h"

#include <libavutil/dovi_meta.h>
#include <libavutil/mem.h>

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

    // Parse and rewrite each UNSPEC62 RPU here when Profile 7 to 8.1 conversion
    // is enabled. Until then the caller retains HDR10 base-layer fallback.
    return 0;
}

void gm_dovi_converter_free(GMDoviConverter **converter) {
    if (!converter || !*converter) return;
    av_freep(converter);
}
