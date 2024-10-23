from scapy.all import *
from collections import OrderedDict
import ipaddress
import random
import sys
import binascii
import socket
import argparse

sys.path.append(os.path.expandvars('$SDE/install/lib/python3.9/site-packages/tofino/bfrt_grpc'))
sys.path.append(os.path.expandvars('$SDE/install/lib/python3.9/site-packages/tofino/'))
sys.path.append(os.path.expandvars('$SDE/install/lib/python3.9/site-packages/'))

import bfrt_grpc.client as gc
print(sys.version)


PKT_TYPE_NORMAL = 0
PKT_TYPE_I2E_MIRROR = 1
PKT_TYPE_E2E_MIRROR = 2



PT_RECIR = [148, 164, 172, 180, 188, 168, 160, 152, 144, 136, 32, 24, 16, 8, 0, 20, 28, 36, 44, 52]

PT_HEADER_RECIR      = [[148, 164], [172, 180], [188, 168], [160, 152], [144, 136], [32, 24], [16, 8], [0, 20], [28, 36], [44, 52]]
PT_HEADER_OUT        = [[140], [132], [156], [184], [176], [56], [48], [40], [4], [12]]

PT_PAY_RECIR         = [[148, 164], [172, 180], [188, 168], [160, 152], [144, 136], [32, 24], [16, 8], [0, 20], [28, 36], [44, 52]]
PT_PAY_OUT           = [[140], [132], [156], [184], [176], [56], [48], [40], [4], [12]]
PT_HOST              = [[60]] * 10



Q_HEADER_RECIR       = 0
Q_HEADER_OUT         = 0
Q_PAY_RECIR          = 1
Q_PAY_OUT            = 0
Q_HOST               = 0

I2E_MIRROR_SIDS = [[1, 2], [3, 4], [5, 6], [7, 8], [9, 10], [11, 12], [13, 14], [15, 16], [17, 18], [19, 20]]



# pktgen rate
ns = 1300

# header handling
# <0 : no mirror
header_recirculated = 8

payload_recirculated = -2


qh_weight = 30
qp_weight = 1

## -- Test configuration


parser = argparse.ArgumentParser() 
parser.add_argument('--ns')
parser.add_argument('--h_recir')
parser.add_argument('--qh_weight')
parser.add_argument('--qp_weight')

args = parser.parse_args()
if args.ns != None:
    ns = int(args.ns)
if args.h_recir != None:
    header_recirculated = int(args.h_recir)
if args.qh_weight != None:
    qh_weight = int(args.qh_weight)
if args.qp_weight != None:
    qp_weight = int(args.qp_weight)


max_m = 16
assert max_m & (max_m - 1) == 0

for ports_set in [PT_HEADER_RECIR, PT_HEADER_OUT, PT_PAY_RECIR, PT_PAY_OUT, PT_HOST]:
    assert len(I2E_MIRROR_SIDS) == len(ports_set)
    
for ports_set in [PT_HEADER_RECIR, PT_HEADER_OUT, PT_PAY_RECIR, PT_PAY_OUT, PT_HOST, I2E_MIRROR_SIDS]:
    for ids in ports_set:
        assert len(ids) & (len(ids) - 1) == 0


print()
print('### Test setting ###')
print('max_m:\t\t%d\n' % max_m)
print('h_recir:\t\t%d\n' % header_recirculated)
print('qh_weight:\t\t%d\n' % qh_weight)
print('qp_weight:\t\t%d\n' % qp_weight)
print()
    
    

print("# client")
grpc_addr = 'localhost:50052'
client_id = 0
device_id = 0
is_master = False
notifications = None
perform_bind = True

interface = gc.ClientInterface(grpc_addr, client_id=1, device_id=0)
# interface = gc.ClientInterface(grpc_addr, client_id=client_id, device_id=device_id, is_master=is_master, notifications=notifications)
bfrt_info = interface.bfrt_info_get()
p4_name = bfrt_info.p4_name_get()
if perform_bind:
    interface.bind_pipeline_config(p4_name)
bfrt_info = interface.bfrt_info_get()
target = gc.Target(device_id=0, pipe_id=0xFFFF)


def entry_tryadd_and_mod(table, target, key_list, data_list):
    try:
        table.entry_add(target, key_list, data_list)
    except gc.BfruntimeReadWriteRpcException as ex:
        table.entry_mod(target, key_list, data_list)


print('# ig: tb_recir_cnt')

table = collections.OrderedDict()
for port in PT_RECIR:
    table[(port, 0)] = ([], 'MyIngressControl.incr_payload_recir_cnt')
    table[(port, 1)] = ([], 'MyIngressControl.incr_header_recir_cnt')

key_list = []
data_list = []
recir_cnt_table = bfrt_info.table_get('MyIngressControl.tb_recir_cnt')
recir_cnt_table.entry_del(target)
for k in table:
    key_list += [recir_cnt_table.make_key([
        gc.KeyTuple('ig_intr_md.ingress_port', k[0]), 
        gc.KeyTuple('hdr.dandc.frag_id', k[1])])]
    data_list += [recir_cnt_table.make_data(table[k][0], table[k][1])]
recir_cnt_table.entry_add(target, key_list, data_list)



print('# ig: tb_mirror')
table = collections.OrderedDict()


for j, ports in enumerate(PT_HEADER_RECIR):
    for ri, port in enumerate(ports):
        if header_recirculated >= 0:
            table[(0, 0, j, (ri, len(ports) - 1))] = ([gc.DataTuple('mirror_sid', I2E_MIRROR_SIDS[j][ri])], 'MyIngressControl.set_mirror')
        else:
            table[(0, 0, j, (ri, len(ports) - 1))] = ([], 'NoAction')

key_list = []
data_list = []
mirror_ig_table = bfrt_info.table_get('MyIngressControl.tb_mirror')
mirror_ig_table.entry_del(target)
for k in table:
    key_list += [mirror_ig_table.make_key([
        gc.KeyTuple('hdr.dandc.payload_recir_cnt', k[0]), 
        gc.KeyTuple('hdr.dandc.header_recir_cnt', k[1]), 
        gc.KeyTuple('hdr.dandc.port', k[2]), 
        gc.KeyTuple('hdr.dandc.entry_id', k[3][0], k[3][1])])]
    data_list += [mirror_ig_table.make_data(table[k][0], table[k][1])]
mirror_ig_table.entry_add(target, key_list, data_list)



print('# ig: tb_port')
table = collections.OrderedDict()

# telemetry packet
for j, ports in enumerate(PT_HOST):
    for ri, port in enumerate(ports):
        table[((254, 0xFF), (0, 0x00), 0, (0, 0x00), j, (ri, len(ports) - 1))]  = ([gc.DataTuple('port', port), gc.DataTuple('qid', Q_HOST)], 'MyIngressControl.set_port')

# payload out
if payload_recirculated >= 0:
    for j, ports in enumerate(PT_PAY_OUT):
        for ri, port in enumerate(ports):
            table[((0, 0xFF), (payload_recirculated, 0xFF), 0, (0, 0x00), j, (ri, len(ports) - 1))] = ([gc.DataTuple('port', port), gc.DataTuple('qid', Q_PAY_OUT)], 'MyIngressControl.set_port_out')
elif payload_recirculated == -2:
    for j, ports in enumerate(PT_PAY_OUT):
        for ri, port in enumerate(ports):
            table[((0, 0xFF), (0, 0x00), 0, (1, 0xFF), j, (ri, len(ports) - 1))] = ([gc.DataTuple('port', port), gc.DataTuple('qid', Q_PAY_OUT)], 'MyIngressControl.set_port_out')

# payload recir
for j, ports in enumerate(PT_PAY_RECIR):
    for ri, port in enumerate(ports):
        table[((0, 0xFF), (0, 0x00), 0, (0, 0x00), j, (ri, len(ports) - 1))] = ([gc.DataTuple('port', port), gc.DataTuple('qid', Q_PAY_RECIR)], 'MyIngressControl.set_port')

# header out
for j, ports in enumerate(PT_HEADER_OUT):
    for ri, port in enumerate(ports):
        table[((header_recirculated, 0xFF), (0, 0xFF), 1, (0, 0x00), j, (ri, len(ports) - 1))] = ([gc.DataTuple('port', port), gc.DataTuple('qid', Q_HEADER_OUT)], 'MyIngressControl.set_port')

# header recir
for j, ports in enumerate(PT_HEADER_RECIR):
    for ri, port in enumerate(ports):
        table[((0, 0x00), (0, 0xFF), 1, (0, 0x00), j, (ri, len(ports) - 1))] = ([gc.DataTuple('port', port), gc.DataTuple('qid', Q_HEADER_RECIR)], 'MyIngressControl.set_port')

key_list = []
data_list = []
port_table = bfrt_info.table_get('MyIngressControl.tb_port')
port_table.entry_del(target)
for k in table:
    key_list += [port_table.make_key([
        gc.KeyTuple('hdr.dandc.header_recir_cnt', k[0][0], k[0][1]), 
        gc.KeyTuple('hdr.dandc.payload_recir_cnt', k[1][0], k[1][1]), 
        gc.KeyTuple('hdr.dandc.frag_id', k[2]), 
        gc.KeyTuple('hdr.dandc.frag_seq', k[3][0], k[3][1]), 
        gc.KeyTuple('hdr.dandc.port', k[4]), 
        gc.KeyTuple('hdr.dandc.entry_id', k[5][0], k[5][1])])]
    data_list += [port_table.make_data(table[k][0], table[k][1])]
port_table.entry_add(target, key_list, data_list)



print('# eg: tb_frag_id')
table = collections.OrderedDict()

table[((0, 0xFF), (0, 0xFF), PKT_TYPE_I2E_MIRROR)] = ([], 'MyEgressControl.get_fid_header')
table[((0, 0xFF), (0, 0xFF), PKT_TYPE_NORMAL)] = ([], 'MyEgressControl.get_fid_payload')
table[((0, 0x00), (0, 0x00), PKT_TYPE_I2E_MIRROR)] = ([], 'MyEgressControl.incr_imirror')
table[((0, 0x00), (0, 0x00), PKT_TYPE_E2E_MIRROR)] = ([], 'MyEgressControl.incr_emirror')

key_list = []
data_list = []
frag_id_table = bfrt_info.table_get('MyEgressControl.tb_frag_id')
frag_id_table.entry_del(target)
for k in table:
    key_list += [frag_id_table.make_key([
        gc.KeyTuple('hdr.dandc.header_recir_cnt', k[0][0], k[0][1]), 
        gc.KeyTuple('hdr.dandc.payload_recir_cnt', k[1][0], k[1][1]), 
        gc.KeyTuple('hdr.mirror.pkt_type', k[2])])]
    data_list += [frag_id_table.make_data(table[k][0], table[k][1])]
frag_id_table.entry_add(target, key_list, data_list)



print('# eg: tb_header_value')
table = collections.OrderedDict()

table[((0, 0xFF), (0, 0xFF), 0)] = ([], 'MyEgressControl.reset_values')
table[((header_recirculated, 0xFF), (0, 0xFF), 1)] = ([], 'MyEgressControl.process_values')

key_list = []
data_list = []
header_value_table = bfrt_info.table_get('MyEgressControl.tb_header_values')
header_value_table.entry_del(target)
for k in table:
    key_list += [header_value_table.make_key([
        gc.KeyTuple('hdr.dandc.header_recir_cnt', k[0][0], k[0][1]), 
        gc.KeyTuple('hdr.dandc.payload_recir_cnt', k[1][0], k[1][1]), 
        gc.KeyTuple('hdr.dandc.frag_id', k[2])])]
    data_list += [header_value_table.make_data(table[k][0], table[k][1])]
header_value_table.entry_add(target, key_list, data_list)



print('# eg: tb_frag_seq')
table = collections.OrderedDict()

table[((0, 0xFF), (0, 0x00), 0)] = ([], 'MyEgressControl.get_seq_payload')
table[((header_recirculated, 0xFF), (0, 0xFF), 1)] = ([], 'MyEgressControl.get_seq_header')

key_list = []
data_list = []
frag_seq_table = bfrt_info.table_get('MyEgressControl.tb_frag_seq')
frag_seq_table.entry_del(target)
for k in table:
    key_list += [frag_seq_table.make_key([
        gc.KeyTuple('hdr.dandc.header_recir_cnt', k[0][0], k[0][1]), 
        gc.KeyTuple('hdr.dandc.payload_recir_cnt', k[1][0], k[1][1]), 
        gc.KeyTuple('hdr.dandc.frag_id', k[2])])]
    data_list += [frag_seq_table.make_data(table[k][0], table[k][1])]
frag_seq_table.entry_add(target, key_list, data_list)



print('# eg: tb_drop_header')
table = collections.OrderedDict()

table[((header_recirculated, 0xFF), (0, 0xFF), 1)] = ([], 'MyEgressControl.drop_all')
table[((0, 0xFF), (max_m, max_m), 0)] = ([], 'MyEgressControl.drop_all')

key_list = []
data_list = []
drop_header_table = bfrt_info.table_get('MyEgressControl.tb_drop_header')
drop_header_table.entry_del(target)
for k in table:
    key_list += [drop_header_table.make_key([
        gc.KeyTuple('hdr.dandc.header_recir_cnt', k[0][0], k[0][1]), 
        gc.KeyTuple('hdr.dandc.payload_recir_cnt', k[1][0], k[1][1]), 
        gc.KeyTuple('hdr.dandc.frag_id', k[2])])]
    data_list += [drop_header_table.make_data(table[k][0], table[k][1])]
drop_header_table.entry_add(target, key_list, data_list)



N_REG_TABLE = 16
print('# eg: tb_reg_match x %d' % N_REG_TABLE)
for l in range(N_REG_TABLE):
    table = collections.OrderedDict()

    table[((0, 0xFF), (0, 0x00), 0, 1)] = ([], 'MyEgressControl.get_data0_%d' % l)
    table[((header_recirculated, 0xFF), (0, 0xFF), 1, 1)] = ([], 'MyEgressControl.set_data0_%d' % l)

    key_list = []
    data_list = []
    reg_match_table = bfrt_info.table_get('MyEgressControl.tb_reg_match_%d' % l)
    reg_match_table.entry_del(target)
    for k in table:
        key_list += [reg_match_table.make_key([
            gc.KeyTuple('hdr.dandc.header_recir_cnt', k[0][0], k[0][1]), 
            gc.KeyTuple('hdr.dandc.payload_recir_cnt', k[1][0], k[1][1]), 
            gc.KeyTuple('hdr.dandc.frag_id', k[2]), 
            gc.KeyTuple('hdr.dandc.frag_seq', k[3])])]
        data_list += [reg_match_table.make_data(table[k][0], table[k][1])]
    reg_match_table.entry_add(target, key_list, data_list)




print("# mirroring")
mirror_cfg_table = bfrt_info.table_get("$mirror.cfg")

ports_set = PT_HEADER_RECIR if header_recirculated > 0 else PT_HEADER_OUT
for j, ports in enumerate(ports_set):
    for ri, port in enumerate(ports):
        sid = I2E_MIRROR_SIDS[j][ri]
        max_len = 121
        
        entry_tryadd_and_mod(mirror_cfg_table, 
            target,
            [mirror_cfg_table.make_key([gc.KeyTuple('$sid', sid)])],
            [mirror_cfg_table.make_data([gc.DataTuple('$direction', str_val="INGRESS"),
                                        gc.DataTuple('$ucast_egress_port', port),
                                        gc.DataTuple('$ucast_egress_port_valid', bool_val=True),
                                        gc.DataTuple('$egress_port_queue', Q_HEADER_RECIR),
                                        gc.DataTuple('$session_enable', bool_val=True),
                                        gc.DataTuple('$max_pkt_len', max_len)],
                                        '$normal')]
        )



print("# lpf")

lpf_table = bfrt_info.table_get('MyEgressControl.lpf_1')

lpf_table.entry_mod(
    target, 
    [lpf_table.make_key([gc.KeyTuple('$LPF_INDEX', 0)])],
    [lpf_table.make_data([gc.DataTuple('$LPF_SPEC_TYPE', str_val="SAMPLE"),
                                gc.DataTuple('$LPF_SPEC_GAIN_TIME_CONSTANT_NS', float_val=100000.),
                                gc.DataTuple('$LPF_SPEC_DECAY_TIME_CONSTANT_NS', float_val=100000.),
                                gc.DataTuple('$LPF_SPEC_OUT_SCALE_DOWN_FACTOR', 0)],
                                None)]
)



print('# tm: queue weights')
for ports in PT_HEADER_RECIR:
    for dev_port in ports:

        pipe_id = dev_port >> 7
        target = gc.Target(device_id=0, pipe_id=pipe_id)
        
        port_cfg_table = bfrt_info.table_get('tf1.tm.port.cfg')
        entries = port_cfg_table.entry_get(target, [port_cfg_table.make_key([gc.KeyTuple('dev_port', dev_port)])])
        for data, _ in entries:
            pg_id = int.from_bytes(data['pg_id'].val, byteorder='big', signed=False)


        q_sched_table = bfrt_info.table_get('tf1.tm.queue.sched_cfg')
        key_list = [
            q_sched_table.make_key([gc.KeyTuple('pg_id', pg_id), gc.KeyTuple('pg_queue', 0)]),
            q_sched_table.make_key([gc.KeyTuple('pg_id', pg_id), gc.KeyTuple('pg_queue', 1)]),
        ]
        data_list = [
            q_sched_table.make_data([gc.DataTuple('dwrr_weight', qh_weight), gc.DataTuple('scheduling_enable', bool_val=True)]),
            q_sched_table.make_data([gc.DataTuple('dwrr_weight', qp_weight), gc.DataTuple('scheduling_enable', bool_val=True)]),
        ]

        q_sched_table.entry_mod(target, key_list, data_list)
        print('Set (dev_port, pipe, pg_id, queue, weight) = (%d, %d, %d, %d, %d)' % (dev_port, pipe_id, pg_id, 0, qh_weight))
        print('Set (dev_port, pipe, pg_id, queue, weight) = (%d, %d, %d, %d, %d)' % (dev_port, pipe_id, pg_id, 1, qp_weight))

target = gc.Target(device_id=0, pipe_id=0xFFFF)


print('ok')