
control MyIngressControl(
    inout headers hdr,
    inout metadata meta,
    in ingress_intrinsic_metadata_t ig_intr_md,
    in ingress_intrinsic_metadata_from_parser_t ig_prsr_md,
    inout ingress_intrinsic_metadata_for_deparser_t ig_dprsr_md,
    inout ingress_intrinsic_metadata_for_tm_t ig_tm_md) {
    
    action drop_all() {
        ig_dprsr_md.drop_ctl = 7;
    }

    table tb_ignore_packet {
        key = {
            hdr.ipv4.dst_addr: exact;
        }
        actions = { drop_all; NoAction; }
        const entries = {
            0x01010101: NoAction();
            0xFFFFFFFF: drop_all();     // dummy
        }
        const default_action = drop_all();
        const size = 2;
    }

    // ---
    action incr_header_recir_cnt() {
        hdr.dandc.header_recir_cnt = hdr.dandc.header_recir_cnt + 1;
    }

    action incr_payload_recir_cnt() {
        hdr.dandc.payload_recir_cnt = hdr.dandc.payload_recir_cnt + 1;
    }

    table tb_recir_cnt {
        key = { 
            ig_intr_md.ingress_port : exact;
            hdr.dandc.frag_id : exact;
        }
        actions = { incr_header_recir_cnt; incr_payload_recir_cnt; NoAction; }
        const size = 256;
    }


    // ---
    
    Register<bit<16>, bit<8>>(size=1, initial_value=0x0000) reg_entry_id;

    RegisterAction<bit<16>, bit<8>, bit<16>>(reg_entry_id) action_entry_id = {
        void apply(inout bit<16> value, out bit<16> rv) { 
            rv = value;
            if (value == ID_MASK) {
                value = 0;
            } else {
                value = value + 1;
            }
        }
    };

    action get_entry_id() {
        hdr.dandc.entry_id = action_entry_id.execute(0); 
    }

    table tb_entry_id {
        key = {
            hdr.dandc.header_recir_cnt : exact;
            hdr.dandc.payload_recir_cnt : exact;
        }
        actions = { get_entry_id; NoAction; }
        const entries = {
            (0, 0) : get_entry_id();
        }
        const size = 2;
    }

    // ---
    
    Random<bit<8>>() random8_0;
    Register<bit<32>, bit<8>>(size=1, initial_value=0x00000000) reg_pkt_id;

    RegisterAction<bit<32>, bit<8>, bit<32>>(reg_pkt_id) action_pkt_id = {
        void apply(inout bit<32> value, out bit<32> rv) { 
            if (hdr.dandc.entry_id == 0) {
                value = value + 1;
            }
            rv = value;
        }
    };

    action get_pkt_id() {
        hdr.dandc.pkt_id = action_pkt_id.execute(0); 
        hdr.dandc.lb = random8_0.get();
    }

    table tb_pkt_id {
        key = { 
            hdr.dandc.header_recir_cnt : exact;
            hdr.dandc.payload_recir_cnt : exact;
        }
        actions = { get_pkt_id; NoAction; }
        const entries = {
            (0, 0) : get_pkt_id();
        }
        const size = 2;
    }

    // ---




    action set_mirror(MirrorId_t mirror_sid) {
        ig_dprsr_md.mirror_type = I2E_MIRROR_TYPE;
        meta.mirror_sid = mirror_sid;
        meta.mirror.pkt_type = PKT_TYPE_I2E_MIRROR;

        meta.mirror.pkt_id = hdr.dandc.pkt_id;
        meta.mirror.entry_id = hdr.dandc.entry_id;
    }
    
    table tb_mirror {
        key = { 
            hdr.dandc.header_recir_cnt : exact;
            hdr.dandc.payload_recir_cnt : exact;
            hdr.dandc.port: exact;
            hdr.dandc.lb: ternary;
        }
        actions = { set_mirror; NoAction; }
        const size = 128;
    }

    // ---
    action set_port(bit<9> port, bit<7> qid) {
        hdr.mirror.setValid();
        hdr.mirror.pkt_type = PKT_TYPE_NORMAL;
        ig_tm_md.ucast_egress_port = port;
        ig_tm_md.qid = qid;
    }

    action set_port_out(bit<9> port, bit<7> qid) {
        hdr.mirror.setValid();
        hdr.mirror.pkt_type = PKT_TYPE_NORMAL;
        ig_tm_md.ucast_egress_port = port;
        ig_tm_md.qid = qid;

        hdr.dandc.header_recir_cnt = 255;
    }

    table tb_port {
        key = {
            hdr.dandc.header_recir_cnt : ternary;
            hdr.dandc.payload_recir_cnt : ternary;
            hdr.dandc.frag_id : exact;
            hdr.dandc.frag_seq : ternary;
            hdr.dandc.port: exact;
            hdr.dandc.lb: ternary;
        }
        actions = {set_port; set_port_out; NoAction; }
        const size = 512;
    }



    // ---

    apply {

        tb_ignore_packet.apply();
        tb_recir_cnt.apply();
        tb_entry_id.apply();
        tb_pkt_id.apply();
        tb_mirror.apply();
        tb_port.apply();
                
    }
}

