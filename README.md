![语言](https://img.shields.io/badge/语言-verilog_(IEEE1364_2001)-9A90FD.svg) ![仿真](https://img.shields.io/badge/仿真-iverilog-green.svg) ![部署](https://img.shields.io/badge/部署-quartus-blue.svg) ![部署](https://img.shields.io/badge/部署-vivado-FF1010.svg)

　

FPGA GZIP compressor
===========================

FPGA-based streaming GZIP (deflate) compressor. Used for universal lossless data compression. Input raw data and output the standard GZIP format (as known as .gz / .tar.gz file format).

基于 **FPGA** 的流式的 **GZIP** (deflate 算法) 压缩器。用于**通用无损数据压缩**：输入原始数据，输出标准的 GZIP 格式，即常见的 .gz / .tar.gz 文件的格式。

　

![diagram.png](./document/diagram.png)

　

* **极简流式接口** ：
  * AXI-stream 输入接口
    * 数据位宽 8-bit ，每周期可输入 1 字节的待压缩数据
    * 输入的长度大于 32 字节的 AXI-stream 包 (packet) 会被压缩为一个独立的 GZIP 数据流
    * 输入的长度小于 32 字节的 AXI-stream 包会被模块丢弃 (不值得压缩) ，不会产生任何输出

  * AXI-stream 输出接口
    * 数据位宽 32-bit
    * 每个输出的 AXI-stream 包是一个独立的 GZIP 数据流 (包括GZIP文件头和文件尾)

* **性能**：
  * 如果输出接口无反压，也即 o_tready 始终=1，则输入接口也一定无反压，也即 o_tready 始终=1 (即使在最坏情况下) 。
    * 这是我刻意设计的，好处是当外部带宽充足时，本模块可跑在确定且最高的性能下 (输入吞吐率=时钟频率)
  * 在 Xilinx Artix-7 xc7a35ticsg324-1L 上时钟频率跑到 128MHz (输入性能为 128MByte/s)
* **资源**：在 Xilinx FPGA 上约占 8200 LUT 和 25 个 BRAM36K 
* **纯 RTL 设计**，在各种 FPGA 型号上都可以部署。
* 支持**几乎完整的 deflate 算法** ：
  * 依照 deflate 算法规范 (RFC1951 [1]) 和 GZIP 格式规范 (RFC1952 [2]) 编写
  * deflate block :
    * 小于 16384 字节的输入 AXI-stream 包当作一个 deflate block
    * 大于 16384 字节的输入 AXI-stream 包分为多个 deflate block , 每个不超过 16384
  * **LZ77 游程压缩**:
    * 搜索距离为 16383 , 范围覆盖整个 deflate block
    * 使用哈希表匹配搜索，哈希表大小=4096

  * **动态 huffman 编码**：
    * 当 deflate block 较大时，建立动态 huffman tree ，包括 literal code tree 和 distance code tree
    * 当 deflate block 较小时，使用静态 huffman tree 进行编码
  * 由于支持了以上功能，压缩率接近 7ZIP 软件在“快速压缩”选项下生成的 .gz 文件 (平均大概差 5%)
  * 依照 GZIP 的规定，生成原始数据的 CRC32 放在 GZIP 的末尾，用于校验。

* 不支持的特性：
  * 不构建动态 code length tree , 而是使用固定 code length tree ，因为它的收益代价比不像动态 literal code tree 和 distance code tree 那么高。
  * 不支持大于 16384 的 deflate block ，目的是降低 BRAM 资源。
  * LZ77游程压缩时，不支持更大的哈希表和多级哈希表，目的是降低 BRAM 资源。
  * 不会根据实际需要动态调整 deflate block 大小，目的是降低复杂度。
  * 由于以上因素，本设计的压缩率往往低于基于软件的 GZIP 压缩。


　

　

# 使用方法

RTL 目录包含了 GZIP 压缩器的设计源码，其中的 [**gzip_compressor_top.v**](./RTL/gzip_compressor_top.v) 是 IP 的顶层模块。

## 模块信号

gzip_compressor_top 的输入输出信号如下

```verilog
module gzip_compressor_top # (
    parameter          SIMULATION = 0     // 0:disable simulation assert (for normal use)  1: enable simulation assert (for simulation)
) (
    input  wire        rstn,              // asynchronous reset.   0:reset   1:normally use
    input  wire        clk,
    // input  stream : AXI-stream slave,  1 byte width (thus do not need tkeep and tstrb)
    output wire        i_tready,
    input  wire        i_tvalid,
    input  wire [ 7:0] i_tdata,
    input  wire        i_tlast,
    // output stream : AXI-stream master, 4 byte width
    input  wire        o_tready,
    output reg         o_tvalid,
    output reg  [31:0] o_tdata,
    output reg         o_tlast,
    output reg  [ 3:0] o_tkeep            // At the end of packet (tlast=1), tkeep may be 4'b0001, 4'b0011, 4'b0111, or 4'b1111. In other cases, tkeep can only be 4'b1111
);
```

　

## 复位

- 令 rstn=0 可复位，之后正常工作时都保持 rstn=1。
- 在大多数 FPGA 上其实可以不用复位就能工作。在少数不支持 `initial` 寄存器初始化的 FPGA 上，使用前必须复位。

　

## 输入接口

输入接口是标准的 8-bit 位宽的 AXI-stream slave

- `i_tvalid` 和 `i_tready` 构成握手信号，只有同时=1时才成功输入了1个数据 (如下图)。
- `i_tdata` 是1字节的输入数据。
- `i_tlast` 是包 (packet) 的分界标志，`i_tlast=1` 意味着当前传输的是一个包的末尾字节，而下一个传输的字节就是下一包的首字节。每个包会被压缩为一个独立的 GZIP 数据流。

```
              _    __    __    __    __    __    __    __    __    __    __    __
     clk       \__/  \__/  \__/  \__/  \__/  \__/  \__/  \__/  \__/  \__/  \__/  \
                          _____________________________             _____
    tvalid    ___________/                             \___________/     \________
              _________________                   ________________________________
    tready                     \_________________/
                          _____ _______________________             _____
    tdata     XXXXXXXXXXXX__D1_X___________D2__________XXXXXXXXXXXXX__D3_XXXXXXXXX  
```

　

## 输出接口

输出接口是标准的 32-bit (4字节) 位宽的 AXI-stream master

- `o_tvalid` 和 `o_tready` 构成握手信号，只有同时=1时才成功输出了1个数据 (类似输入接口) 。
- `o_tdata` 是4字节的输出数据。按照 AXI-stream 的规定，`o_tdata` 是小端序，`o_tdata[7:0]` 是最靠前的字节，`o_data[31:24]` 是最靠后的字节。
- `o_tlast` 是包的分界标志。每个包是一个独立的 GZIP 数据流。
- `o_tkeep` 是字节有效信号：
  - `o_tkeep[0]=1` 意为 `o_tdata[7:0]` 有效，否则无效
  - `o_tkeep[1]=1` 意为 `o_tdata[15:8]` 有效，否则无效
  - `o_tkeep[2]=1` 意为 `o_tdata[23:16]` 有效，否则无效
  - `o_tkeep[3]=1` 意为 `o_tdata[31:24]` 有效，否则无效
- 当输出包的字节数量不能整除4时，只有在包的末尾 (`o_tlast=1` 时) ，`o_tkeep` 才可能为 `4'b0001, 4'b0011, 4'b0111` 
- 其余情况下 `o_tkeep=4’b1111`

　

## 输出格式

AXI-stream 接口输出的是满足 GZIP 格式标准的数据，将每个 AXI-stream 包的数据独立存入一个 .gz 文件后，这个文件就可以被众多压缩软件 (7ZIP, WinRAR 等) 解压。

> 提示： .gz 是 GZIP 压缩文件的概念。更为人熟知的是 .tar.gz 。实际上 TAR 是把多个文件打包成一个 .tar 文件，然后再对这一个 .tar 文件进行 GZIP 压缩得到 .tar.gz 文件。如果对单个文件进行压缩，则可以不用 TAR 打包，直接压缩为一个 .gz 。例如 data.txt 压缩为 data.txt.gz

例如，AXI-stream 接口上一共成功握手了 987 次，最后一次握手时 `o_tlast=1` ，说明这 35 拍数据是一个独立的 GZIP 流。假设最后一次握手时 `o_tkeep=4'b0001` ，则最后一拍只携带1字节的数据，则该 GZIP 流一共包含 986×4+1=3949 字节。如果将这些字节存入 .gz 文件，则应该：

```
.gz 文件的第1字节 对应 第1拍的 o_tdata[7:0]
.gz 文件的第2字节 对应 第1拍的 o_tdata[15:8]
.gz 文件的第3字节 对应 第1拍的 o_tdata[23:16]
.gz 文件的第4字节 对应 第1拍的 o_tdata[31:24]
.gz 文件的第5字节 对应 第2拍的 o_tdata[7:0]
.gz 文件的第6字节 对应 第2拍的 o_tdata[15:8]
.gz 文件的第7字节 对应 第2拍的 o_tdata[23:16]
.gz 文件的第8字节 对应 第2拍的 o_tdata[31:24]
......
.gz 文件的第3945字节 对应 第986拍的 o_tdata[7:0]
.gz 文件的第3946字节 对应 第986拍的 o_tdata[15:8]
.gz 文件的第3947字节 对应 第986拍的 o_tdata[23:16]
.gz 文件的第3948字节 对应 第986拍的 o_tdata[31:24]
.gz 文件的第3949字节 对应 第987拍的 o_tdata[7:0]
```

　

## 其它注意事项

- 如果输出接口无反压，也即 `o_tready` 始终=1，则输入接口也一定无反压，也即 `o_tready` 始终=1 (即使在最坏情况下) 。
  - 借助这个特性，如果外部带宽充足稳定，以至于可以保证  `o_tready` 始终=1 ，则可忽略 `i_tready` 信号，任何时候都可以让 `i_tvalid=1` 来输入一个字节。
- deflate 算法需要用整个 deflate block 来构建动态 huffman 树，因此本模块的端到端延迟较高：
  - 当输入 AXI-stream 包长度为 32\~16384 时，只有在输入完完整的包 (并还需要过一段时间后) ，才能在输出 AXI-stream 接口上拿到对应的压缩包的第一个数据。
  - 当输入 AXI-stream 包长度 >16384 时，每完整地输入完 16384 字节 (并还需要过一段时间后)，才能在输出 AXI-stream 接口上拿到对应的有关这部分数据的压缩数据、
- 当输入 AXI-stream 包长度为 <32 时，模块内部会丢弃该包，并且不会针对它产生任何输出数据。
- 要想获得高压缩率，尽量让包长度 >7000 字节，否则模块很可能不会选择使用动态 huffman ，且 LZ77 的搜索范围也会很受限。如果需要压缩的数据在逻辑上是很多很小的 AXI-stream 包，可以在前面加一个预处理器，把它们合并为一个几千或几万字节的大包来送入 gzip_compressor_top 。

　

　

# 仿真

SIM 目录包含了 GZIP 压缩器的 testbench 源码。该 testbench 的框图如下：

![testbench_diagram.png](./document/testbench_diagram.png)

　

其中随机数据包生成器 (tb_random_data_source.v) 会4种生成特性不同的数据包 (字节概率均匀分布的随机数据、字节概率非均匀分布的随机数据、随机连续变化的数据、稀疏数据) ，送入待测模块 (gzip_compressor_top) 进行压缩，然后 tb_save_result_to_file 模块会把压缩结果存入文件，每个独立的数据包存入一个独立的 .gz 文件。

tb_print_crc32 负责计算原始数据的 CRC32 并打印，注意：待测模块内部也会计算 CRC32 并封装入 GZIP 数据流，这两个 CRC32 计算器是独立的 (前者仅用于仿真，用来验证待测模块生成的 CRC32 是否正确)。你可以自行将仿真打印的 CRC32 与 生成的 GZIP 文件中的 CRC32 进行对比。

## 使用 iverilog 仿真

你可以按照以下步骤进行 iverilog 仿真：

* 需要先安装 iverilog ，见教程：[iverilog_usage](https://github.com/WangXuan95/WangXuan95/blob/main/iverilog_usage/iverilog_usage.md) 。
* 然后直接双击 tb_gzip_compressor_run_iverilog.bat 文件就能运行仿真 (仅限Windows) 。tb_gzip_compressor_run_iverilog.bat 包含了执行 iverilog 仿真的命令。
* 随机数据包生成器默认会生成 10 个数据包，你可以通过修改 tb_random_data_source.v 里的宏名 `FILE_COUNT` 来修改数量。在10个文件的情况下，仿真一般要运行十几分钟才能结束。
* 仿真生成的 GZIP 压缩流会存放于 sim_data 目录 (你可以通过修改 tb_save_result_to_file.v 里的宏名 `OUT_FILE_PATH` 来修改存放的目录)
  * 仿真会生成几百个 .gz 文件，你可以直接用 7ZIP 、WinRAR 等压缩软件来解压它们。
* 为了批量检查仿真生成的文件有没有格式错误， 可以运行 sim_data 目录里的 python 源文件 check_gz_file.py ，你需要在 sim_data 目录里打开命令行 (CMD) 用以下指令来运行：

```powershell
python check_gz_file.py .
```

以上命令意为：对当前目录 (.) ，也即 sim_data 目录下的所有 .gz 文件进行批量检查。

## 使用其它仿真器

除了 iverilog ，你也可以用其它仿真器来仿真。只需要把 RTL 和 SIM 目录里的所有 .v 文件加入仿真工程，并以 tb_gzip_compressor.v 为仿真顶层进行仿真即可。

　

　

# 部署结果

gzip_compressor_top 在各种 FPGA 上实现的结果：

|    FPGA 系列    |      FPGA 型号      | 逻辑资源 | 逻辑资源(%) |  片上存储   | 片上存储(%) | 最高频率 |
| :-------------: | :-----------------: | :------: | :---------: | :---------: | :---------: | :------: |
| Xilinx Artix-7  |  xc7a35ticsg324-1L  | 8218*LUT |     40%     | 25*BRAM36K  |     50%     | 128 MHz  |
|  Xilinx Zynq-7  |   xc7z020clg484-1   | 8218*LUT |     16%     | 25*BRAM36K  |     18%     | 128 MHz  |
| Xilinx Virtex-7 | xc7vx485tffg1761-1  | 8201*LUT |     3%      | 25*BRAM36K  |     3%      | 160 MHz  |
|   Xilinx ZU+    | xczu3eg-sbva484-2-e | 8180*LUT |     12%     | 24*BRAM36K  |     11%     | 280 MHz  |
| Altera Cyclone4 |    EP4CE55F23C8     | 16807*LE |     30%     | 807398 bits |     34%     |  74 MHz  |

　

　

# FPGA 部署运行

我提供了一个基于串口的 FPGA 部署运行示例，该工程跑在 [Arty开发板](https://china.xilinx.com/products/boards-and-kits/arty.html) 上 (该工程也全都是纯 RTL 设计，可以直接移植到其它 FPGA 型号上)。

该 FPGA 工程接收串口数据，将数据送入 GZIP 压缩器，并将得到的 GZIP 压缩数据流用串口发出去 (串口格式: 波特率115200, 无校验位)。

在电脑 (上位机) 上，编写了一个 python 程序，该程序的执行步骤是：

- 从电脑的磁盘中读入一个文件 (用户通过命令行指定文件名)；
- 列出电脑上的所有串口，用户需要选择 FPGA 对应的串口 (如果只发现一个串口，则直接选择这个串口)
- 将该文件的所有字节通过串口发给 FPGA；
- 同时接口 FPGA 发来的数据；
- 将接收到的数据存入一个 .gz 文件，相当于调用 FPGA 进行了文件压缩。
- 最终，调用 python 的 gzip 库解压该 .gz 文件，并与原始数据相比，看是否相等。如果不相等则报错。

> 由于串口速度远小于 gzip_compressor_top 能达到的最高性能，因此该工程仅仅用于展示。要想让 gzip_compressor_top 发挥更高性能，需要用其它高速通信接口。

下图是该工程的框图。

![fpga_test_diagram.png](./document/fpga_test_diagram.png)

　

有关该工程的文件：

- Arty-example/RTL 里是 FPGA 工程源码 (除了 gzip_compressor_top 的源码，gzip_compressor_top 的源码在根目录的 ./RTL 里)
- Arty-example/vivado 里是 vivado 工程
- Arty-example/python 里是 python 上位机程序 (`fpga_uart_gz_file.py`)

FPGA 工程烧录后，在 Arty-example/python 目录下打开命令行，运行以下命令：

```powershell
python fpga_uart_gz_file.py <需要压缩的文件名>
```

例如，运行以下命令，相当于把 `fpga_uart_gz_file.py` 这个文件自己送给 FPGA 压缩了：

```powershell
python fpga_uart_gz_file.py fpga_uart_gz_file.py
```

如果压缩成功，会得到 `fpga_uart_gz_file.py.gz` 文件，且不会打印报错信息。

　

　

# 参考资料

[1] RFC 1951 : DEFLATE Compressed Data Format Specification version 1.3. https://www.rfc-editor.org/rfc/rfc1951

[2] RFC 1952 : GZIP file format specification version 4.3. https://www.rfc-editor.org/rfc/rfc1952