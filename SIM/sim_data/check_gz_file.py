
import sys
import os
import gzip


if __name__ == '__main__' :
    
    try :
        INPUT_DIR_NAME = sys.argv[1]
        fname_list = os.listdir(INPUT_DIR_NAME)
    except Exception as ex :
        print(str(ex))
        exit()
    
    # only keep the file name ends with '.gz'
    fname_list = list(filter(lambda fname:fname.endswith('.gz'), fname_list))
    
    if len(fname_list) <= 0 :
        print('no .gz file found')
        exit()
    
    error_count = 0
    compressed_size = 0
    decompressed_size = 0
    
    for fname in fname_list :
        fname_full = INPUT_DIR_NAME + os.path.sep + fname
        
        try :
            with open(fname_full, 'rb') as fp :
                decompressed_size += len(gzip.GzipFile(mode='rb', fileobj=fp).read())
            compressed_size += os.path.getsize(fname_full)
        except Exception as ex :
            print('%s de-compress failed : %s' % (fname, str(ex)) )
            error_count += 1
    
    print('\nSummary :')
    
    print('  total %d files' % len(fname_list) )
    
    if error_count == 0 :
        print('  no error')
    else :
        print('  error %d files !!' % error_count )
    
    print('  total    compressed size = %d bytes' % compressed_size   )
    print('  total de-compressed size = %d bytes' % decompressed_size )
    print('  compression ratio        = %.2f%%'   % (100.0 * (compressed_size+1) / (decompressed_size+1)) )

