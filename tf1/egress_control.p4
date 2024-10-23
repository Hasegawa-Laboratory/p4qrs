#include "register_store2.p4"

control MyEgressControl(
    inout headers hdr,
    inout metadata meta,
    in egress_intrinsic_metadata_t eg_intr_md,
    in egress_intrinsic_metadata_from_parser_t eg_prsr_md,
    inout egress_intrinsic_metadata_for_deparser_t eg_dprsr_md,
    inout egress_intrinsic_metadata_for_output_port_t eg_oport_md) {
    
    // ---

    action get_fid_header() {
        hdr.dandc.frag_id = 1;

        hdr.dandc.pkt_id = hdr.mirror.pkt_id;
        hdr.dandc.entry_id = hdr.mirror.entry_id;

        hdr.dandc.imirror_cnt = hdr.dandc.imirror_cnt + 1;
    }

    action get_fid_payload() {
        hdr.dandc.frag_id = 0;
    }

    action incr_imirror() {
        hdr.dandc.imirror_cnt = hdr.dandc.imirror_cnt + 1;
    }

    action incr_emirror() {
        hdr.dandc.emirror_cnt = hdr.dandc.emirror_cnt + 1;
    }

    table tb_frag_id {
        key = {
            hdr.dandc.header_recir_cnt : ternary;
            hdr.dandc.payload_recir_cnt : ternary;
            hdr.mirror.pkt_type : exact;
        }
        actions = { get_fid_header; get_fid_payload; incr_imirror; incr_emirror; NoAction; }
        const size = 4;
    }

    // ---

    action reset_values() {
        hdr.frag_0.v_0 = 0;
    }

    action process_values() {
        hdr.frag_0.v_0 = hdr.dandc.pkt_id;
        hdr.frag_0.v_1 = 0xDEADBEEF;
        hdr.frag_0.v_2 = 0xDEADBEEF;
        hdr.frag_0.v_3 = 0xDEADBEEF;
        hdr.frag_0.v_4 = 0xDEADBEEF;
        hdr.frag_0.v_5 = 0xDEADBEEF;
        hdr.frag_0.v_6 = 0xDEADBEEF;
        hdr.frag_0.v_7 = 0xDEADBEEF;
        hdr.frag_0.v_8 = 0xDEADBEEF;
        hdr.frag_0.v_9 = 0xDEADBEEF;
        hdr.frag_0.v_10 = 0xDEADBEEF;
        hdr.frag_0.v_11 = 0xDEADBEEF;
        hdr.frag_0.v_12 = 0xDEADBEEF;
        hdr.frag_0.v_13 = 0xDEADBEEF;
        hdr.frag_0.v_14 = 0xDEADBEEF;
        hdr.frag_0.v_15 = 0xDEADBEEF;
    }

    table tb_header_values {
        key = {
            hdr.dandc.header_recir_cnt : ternary;
            hdr.dandc.payload_recir_cnt : ternary;
            hdr.dandc.frag_id : exact;
        }
        actions = { reset_values; process_values; NoAction; }
        const size = 2;
    }

    // ---

        Register<pair, bit<16>>(size=ID_SIZE, initial_value={0, 0}) reg_frag_seq;

    RegisterAction<pair, bit<16>, bit<32>>(reg_frag_seq) action_header_seq = {
        void apply(inout pair value, out bit<32> rv) { 
            if (value.second != hdr.dandc.pkt_id) {
                value.first = 1;
                rv = value.first;
                value.second = hdr.dandc.pkt_id;
            } else {
                value.first = value.first + 1;
                rv = value.first;
            }
        }
    };

    RegisterAction<pair, bit<16>, bit<32>>(reg_frag_seq) action_payload_seq = {
        void apply(inout pair value, out bit<32> rv) { 
            if (value.second != hdr.dandc.pkt_id) {
                value.first = 0;
                rv = value.first;
            } else {
                rv = value.first;
            }
        }
    };

    action get_seq_header() {
        hdr.dandc.frag_seq = action_header_seq.execute(hdr.dandc.entry_id)[7:0];
    }

    action get_seq_payload() {
        hdr.dandc.frag_seq = action_payload_seq.execute(hdr.dandc.entry_id)[7:0];
    }

    table tb_frag_seq {
        key = {
            hdr.dandc.header_recir_cnt : ternary;
            hdr.dandc.payload_recir_cnt : ternary;
            hdr.dandc.frag_id : exact;
        }
        actions = { get_seq_header; get_seq_payload; NoAction; }
        const size = 2;
    }

    // ---


    action drop_all() {
        eg_dprsr_md.drop_ctl = 7;
    }

    table tb_drop_header {
        key = {
            hdr.dandc.header_recir_cnt : ternary;
            hdr.dandc.payload_recir_cnt : ternary;
            hdr.dandc.frag_id : exact;
        }
        actions = { drop_all; NoAction; }
        const size = 2;
    }

    // ---

    REGISTER(0)
    REGISTER(1)
    REGISTER(2)
    REGISTER(3)
    REGISTER(4)
    REGISTER(5)
    REGISTER(6)
    REGISTER(7)
    REGISTER(8)
    REGISTER(9)
    REGISTER(10)
    REGISTER(11)
    REGISTER(12)
    REGISTER(13)
    REGISTER(14)
    REGISTER(15)

    // ---

    action shift_recir_cnt() {
        hdr.dandc.shifted_emirror_cnt = hdr.dandc.payload_recir_cnt ++ 8w0;
    }

    table tb_ema_1 {
        key = {
            hdr.dandc.header_recir_cnt : exact;
            eg_dprsr_md.mirror_type: ternary;
        }
        actions = { shift_recir_cnt; NoAction; }
        const entries = {
            (255, E2E_MIRROR_TYPE) : shift_recir_cnt();
            (255, _) : shift_recir_cnt();
        }
        const size = 2;
    }

    // ---

    Lpf<bit<16>, bit<8>>(size=1) lpf_1;

    action apply_lpf() {
        hdr.dandc.shifted_emirror_cnt = lpf_1.execute(hdr.dandc.shifted_emirror_cnt, 0);
    }

    table tb_ema_2 {
        key = {
            hdr.dandc.header_recir_cnt : exact;
            eg_dprsr_md.mirror_type: ternary;
        }
        actions = { apply_lpf; NoAction; }
        const entries = {
            (255, E2E_MIRROR_TYPE) : apply_lpf();
            (255, _) : apply_lpf();
        }
        const size = 2;
    }

    // ---

    Register<bit<16>, bit<8>>(size=1, initial_value=0x00) reg_value;

    RegisterAction<bit<16>, bit<8>, bit<16>>(reg_value) action_read_value = {
        void apply(inout bit<16> value, out bit<16> rv) { 
            rv = value;
        }
    };
    
    RegisterAction<bit<16>, bit<8>, void>(reg_value) action_write_value = {
        void apply(inout bit<16> value) { 
            value = hdr.dandc.shifted_emirror_cnt;
        }
    };
    
    action read_value() {
        hdr.dandc.shifted_emirror_cnt = action_read_value.execute(0); 
    }
    
    action write_value() {
        action_write_value.execute(0); 
    }

    table tb_store_value {
        key = {
            hdr.dandc.header_recir_cnt : exact;
            eg_dprsr_md.mirror_type: ternary;
        }
        actions = { read_value; write_value; NoAction; }
        const entries = {
            (255, E2E_MIRROR_TYPE) : write_value();
            (254, E2E_MIRROR_TYPE) : read_value();
            (255, _) : write_value();
            (254, _) : read_value();
        }
        const size = 4;
    }


    // ---

    action drop_mirror_header() {
        hdr.mirror.setInvalid();
    }

    table tb_drop_mirror_header {
        key = {
            hdr.dandc.pkt_id : ternary;
        }
        actions = { drop_mirror_header; NoAction; }
        const entries = {
            _ : drop_mirror_header();
        }
        const size = 1;
    }


    // ---

    apply {

        tb_frag_id.apply();
        tb_header_values.apply();
        tb_frag_seq.apply();
        tb_drop_header.apply();

        tb_reg_match_0.apply();
        tb_reg_match_1.apply();
        tb_reg_match_2.apply();
        tb_reg_match_3.apply();
        tb_reg_match_4.apply();
        tb_reg_match_5.apply();
        tb_reg_match_6.apply();
        tb_reg_match_7.apply();
        tb_reg_match_8.apply();
        tb_reg_match_9.apply();
        tb_reg_match_10.apply();
        tb_reg_match_11.apply();
        tb_reg_match_12.apply();
        tb_reg_match_13.apply();
        tb_reg_match_14.apply();
        tb_reg_match_15.apply();
        
        tb_ema_1.apply();
        tb_ema_2.apply();
        tb_store_value.apply();

        if (hdr.dandc.frag_id == 0 && hdr.dandc.header_recir_cnt == 255 && hdr.dandc.pkt_id != hdr.frag_0.v_0) {
            eg_dprsr_md.drop_ctl = 1;
        }

        tb_drop_mirror_header.apply();

    }
}
