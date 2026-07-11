#ifndef GM_DOVI_H
#define GM_DOVI_H

#include <libavcodec/packet.h>
#include <libavcodec/codec_par.h>

typedef struct GMDoviConverter GMDoviConverter;

GMDoviConverter *gm_dovi_converter_create(const AVCodecParameters *codecpar);
int gm_dovi_converter_profile(const GMDoviConverter *converter);
int gm_dovi_converter_transform_packet(GMDoviConverter *converter, AVPacket *packet);
void gm_dovi_converter_free(GMDoviConverter **converter);

#endif
