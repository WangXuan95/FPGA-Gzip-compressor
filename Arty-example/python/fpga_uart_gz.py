
import sys
import os
import gzip
from serial import Serial
from serial.tools import list_ports





def listAndSelectPort () :
    port_list = list(list_ports.comports())
    
    if len(port_list) <= 0 :
        print('**error: There are no ports detected')
        return None
    
    for port_i, port_info in enumerate(port_list) :
        print('  %d.  %s  hwid=%s' % (port_i, port_info.description, port_info.hwid) )
    
    if len(port_list) == 1 :
        return port_list[0].name
    
    while True :
        port_i_str = input('Please select a port (enter a number): ')
        try :
            port_i = int(port_i_str)
            assert port_i >= 0 and port_i < len(port_list)
        except :
            continue
        return port_list[port_i].name




def readPortUntilEmpty (port) :
    rdata_acc = b''
    while True :
        rdata = port.read(1024)
        if len(rdata) <= 0 :
            break
        rdata_acc += rdata
    return rdata_acc




def GzipCompressUsePort (port_name, data, chunk_len=16384) :
    if len(data) >= (1<<24) :
        return None, '**error: data to be compressed cannot be larger than %d bytes' % (1<<24)
    
    try :
        port = Serial(port_name, baudrate=115200, timeout=1.0)
    except :
        return None, '**error: Unable to open port %s' % port_name
    
    # 封装一个私有的 header ， FPGA 收到该 header 后，从中取出数据长度字段。
    # FPGA 代码文件 rx_parse_packet.v 用来解析该 header
    header = b'\xEB\x9A\xFC\x1D\x98\x30\xB7\x06' + bytes( [ (len(data)&0xFF) , ((len(data)>>8)&0xFF) , ((len(data)>>16)&0xFF) ] ) + b'\x00'
    
    try :
        port.write(header)
    except :
        port.close()
        return None, '**error: port %s write error' % port_name
    
    gz_data = b''
    
    for i in range(0, len(data), chunk_len) :
        j = min( i+chunk_len, len(data) )                                 # i 是 chunk 起始下标, j 是 chunk 结束下标
        chunk = data[i:j]                                                 # 从 data 中取一个 chunk ，长度最大为 chunk_len
        
        try :
            port.write(chunk)                                             # 串口发送数据块
        except :
            port.close()
            return None, '**error: port %s write error' % port_name
        
        try :
            gz_data += readPortUntilEmpty(port)                           # 串口接收并拼接到 gz_data 上
        except :
            port.close()
            return None, '**error: port %s read error' % port_name
        
        print('  chunk %d-%d    (%.2f%%)    gzip length = %d' % (i, j, (100*j/len(data)), len(gz_data) ) )
    
    port.close()
    
    if len(gz_data) <= 0:
        return None, '**error: no read data on port %s' % port_name
    
    return gz_data, ''




if __name__ == '__main__' :
    
    # get input file name from command line arg -------------------------------------------------------------------
    try :
        in_fname = sys.argv[1]
    except :
        print('Usage :  python  %s  <file_name>' % sys.argv[0])
        exit(-1)
    
    # construct output file name -------------------------------------------------------------------
    out_fname = os.path.split(in_fname)[-1] + '.gz'
    
    # open input file -------------------------------------------------------------------
    try :
        with open(in_fname, 'rb') as fp :
            orig_data = fp.read()
    except :
        print('**error: open %s failed' % in_fname)
    
    print('  original data length = %d bytes' % len(orig_data) )
    
    # list and get port name -------------------------------------------------------------------
    port_name = listAndSelectPort()
    
    if port_name is None :
        exit(-1)
    
    # compress data use FPGA via port, get gz_data -------------------------------------------------------------------
    gz_data, err_msg = GzipCompressUsePort(port_name, orig_data)
    
    if gz_data is None :
        print(err_msg)
        exit(-1)
    
    # save gz_data to output file -------------------------------------------------------------------
    with open(out_fname, 'wb') as fp :
        fp.write(gz_data)
    
    # use gzip lib to de-compress gz_data, get ungz_data -------------------------------------------------------------------
    try :
        ungz_data = gzip.decompress(gz_data)
    except Exception as ex :
        print('**error: de-compress failed : %s' % str(ex) )
        exit(-1)
    
    # compare ungz_data with orig_data -------------------------------------------------------------------
    if len(orig_data) != len(ungz_data)  or  orig_data != ungz_data :
        print('**error: ungzip data and original data mismatch')
        exit(-1)
    



