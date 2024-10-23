#define REGISTER(FIELD) \
    Register<bit<32>, bit<16>>(size=ID_SIZE, initial_value=0xAA) BOOST_PP_CAT(reg_, FIELD); \
\
    RegisterAction<bit<32>, bit<16>, void>(BOOST_PP_CAT(reg_, FIELD)) BOOST_PP_CAT(set_action0_, FIELD) = { \
        void apply(inout bit<32> value) { \
            value = hdr.frag_0.BOOST_PP_CAT(v_, FIELD); \
        } \
    }; \
\
    RegisterAction<bit<32>, bit<16>, bit<32>>(BOOST_PP_CAT(reg_, FIELD)) BOOST_PP_CAT(get_action_, FIELD) = { \
        void apply(inout bit<32> value, out bit<32> rv) { \
            rv = value; \
        } \
    }; \
\
    action BOOST_PP_CAT(set_data0_, FIELD)() { \
        BOOST_PP_CAT(set_action0_, FIELD).execute(hdr.dandc.entry_id); \
    } \
\
    action BOOST_PP_CAT(get_data0_, FIELD)() { \
        hdr.frag_0.BOOST_PP_CAT(v_, FIELD) = BOOST_PP_CAT(get_action_, FIELD).execute(hdr.dandc.entry_id); \
    } \
\
    table BOOST_PP_CAT(tb_reg_match_, FIELD) { \
        key = { \
            hdr.dandc.header_recir_cnt : ternary; \
            hdr.dandc.payload_recir_cnt : ternary; \
            hdr.dandc.frag_id : exact; \
            hdr.dandc.frag_seq : exact; \
        } \
        actions = { BOOST_PP_CAT(get_data0_, FIELD); BOOST_PP_CAT(set_data0_, FIELD); NoAction; } \
        /*
        const entries = { \
            (1, 1, 1) : BOOST_PP_CAT(set_data0_, FIELD)(); \
            (0, 0, 1) : BOOST_PP_CAT(get_data0_, FIELD)(); \
        } \
        */ \
        const size = 2; \
    }
