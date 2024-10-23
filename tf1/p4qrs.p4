#include <core.p4>
#include <tna.p4>
#include <boost/preprocessor.hpp>

#include "common/headers.p4"
#include "common/util.p4"

#define ID_SIZE 32768
const bit<16> ID_MASK = ID_SIZE - 1;

const MirrorType_t I2E_MIRROR_TYPE = 1;
const MirrorType_t E2E_MIRROR_TYPE = 2;

typedef bit<8> pkt_type_t;
const pkt_type_t PKT_TYPE_NORMAL = 0;
const pkt_type_t PKT_TYPE_I2E_MIRROR = 1;
const pkt_type_t PKT_TYPE_E2E_MIRROR = 2;


struct pair {
    bit<32> first;
    bit<32> second;
}

struct pair16 {
    bit<16> first;
    bit<16> second;
}

header mirror_h {
    pkt_type_t pkt_type;
    bit<32> pkt_id;
    bit<16> entry_id;
}

header dandc_h {
    bit<32> pkt_id;
    bit<16> entry_id;
    bit<8> frag_id;
    bit<8> frag_seq;

    bit<8> header_recir_cnt;
    bit<8> payload_recir_cnt;

    bit<8> imirror_cnt;
    bit<8> emirror_cnt;
    
    bit<8> port;
    bit<16> shifted_emirror_cnt;

    bit<8> padding;
}

header frag_h {
    bit<32> v_0;
    bit<32> v_1;
    bit<32> v_2;
    bit<32> v_3;
    bit<32> v_4;
    bit<32> v_5;
    bit<32> v_6;
    bit<32> v_7;
    bit<32> v_8;
    bit<32> v_9;
    bit<32> v_10;
    bit<32> v_11;
    bit<32> v_12;
    bit<32> v_13;
    bit<32> v_14;
    bit<32> v_15;
}

struct headers {
    mirror_h mirror;
    ethernet_h ethernet;
    ipv4_h ipv4;

    dandc_h dandc;
    frag_h frag_0;
}

struct metadata {
    MirrorId_t mirror_sid;    
    mirror_h mirror;
}


parser MyIngressParser(packet_in packet,
                out headers hdr,
                out metadata meta,
                out ingress_intrinsic_metadata_t ig_intr_md) {

    TofinoIngressParser() tofino_parser;

    state start {
        tofino_parser.apply(packet, ig_intr_md);
        transition parse_ethernet;
    }

    state parse_ethernet {
        packet.extract(hdr.ethernet);
        transition parse_ipv4;
    }

    state parse_ipv4 {
        packet.extract(hdr.ipv4);
        transition parse_dandc;
    }

    state parse_dandc {
        packet.extract(hdr.dandc);
        transition parse_frag;
    }
    
    state parse_frag {
        packet.extract(hdr.frag_0);
        transition accept;
    }

}


#include "ingress_control.p4"


control MyIngressDeparser(
    packet_out packet, 
    inout headers hdr, 
    in metadata meta,
    in ingress_intrinsic_metadata_for_deparser_t ig_dprsr_md) {
    
    Mirror() mirror;

    apply {

        if (ig_dprsr_md.mirror_type == I2E_MIRROR_TYPE) {
            mirror.emit<mirror_h>(meta.mirror_sid, meta.mirror);
        }

        packet.emit(hdr);
    }
}


parser MyEgressParser(
    packet_in packet,
    out headers hdr,
    out metadata meta,
    out egress_intrinsic_metadata_t eg_intr_md) {

    TofinoEgressParser() tofino_parser;

    state start {
        tofino_parser.apply(packet, eg_intr_md);
        transition parse_mirror;
    }

    state parse_mirror {
        packet.extract(hdr.mirror);
        transition parse_ethernet;
    }

    state parse_ethernet {
        packet.extract(hdr.ethernet);
        transition parse_ipv4;
    }

    state parse_ipv4 {
        packet.extract(hdr.ipv4);
        transition parse_dandc;
    }

    state parse_dandc {
        packet.extract(hdr.dandc);
        transition parse_frag;
    }
    
    state parse_frag {
        packet.extract(hdr.frag_0);
        transition accept;
    }

}


#include "egress_control.p4"


control MyEgressDeparser(
    packet_out packet,
    inout headers hdr,
    in metadata meta,
    in egress_intrinsic_metadata_for_deparser_t eg_dprsr_md) {
        
    Mirror() mirror;

    apply {
        if (eg_dprsr_md.mirror_type == E2E_MIRROR_TYPE) {
            mirror.emit<mirror_h>(meta.mirror_sid, meta.mirror);
        }

        packet.emit(hdr);
    }
}


Pipeline(
    MyIngressParser(),
    MyIngressControl(),
    MyIngressDeparser(),
    MyEgressParser(),
    MyEgressControl(),
    MyEgressDeparser()) pipe;

Switch(pipe) main;
