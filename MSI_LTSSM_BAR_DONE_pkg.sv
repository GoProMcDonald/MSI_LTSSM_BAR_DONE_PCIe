`ifndef PCIE_PKG_SV// 防止重复包含
`define PCIE_PKG_SV// 包含保护宏
`include "uvm_macros.svh"// 引入 UVM 宏定义
//整个文件是一个 SystemVerilog 包（package），用于定义 PCIe 相关的枚举类型、分析端口、序列项类、覆盖率采集组件、sequencer、driver 和 monitor 等。
package pcie_pkg;
  import uvm_pkg::*;// 引入 UVM 包宏定义
  typedef enum bit [1:0] {// 定义一个枚举类型 tlp_type_e，表示 TLP 的事务类型。枚举类型是 SystemVerilog 中的一种数据类型，用于定义一组命名的常量。这里定义了四种 TLP 事务类型：内存读、内存写、配置读和配置写。

    TLP_MRd   = 2'd0,//TLP_MRd 表示内存读事务，值为 2'b00
    TLP_MWr   = 2'd1,// TLP_MWr 表示内存写事务，值为 2'b01
    TLP_CfgRd = 2'd2,// TLP_CfgRd 表示配置读事务，值为 2'd2
    TLP_CfgWr = 2'd3// TLP_CfgWr 表示配置写事务，值为 2'd3
  } tlp_type_e;//枚举类型是 SystemVerilog 中的一种数据类型，用于定义一组命名的常量。这里定义了四种 TLP 事务类型：内存读、内存写、配置读和配置写。

  //  BAR/CFG 常量
  localparam logic [63:0] CFG_BAR0_BASE_ADDR = 64'hFFFF_FF00;
  localparam logic [63:0] CFG_BAR0_SIZE_ADDR = 64'hFFFF_FF08;
  localparam int unsigned DEFAULT_BAR0_SIZE  = 4096;      // 4KB
  localparam logic [31:0] ERR_CODE_ILLEGAL   = 32'hE11E_BADC;
  localparam logic [63:0] MSI_ADDR = 64'hFEE0_0000_0000_1000;

  // -------- 分析端口声明 --------
  `uvm_analysis_imp_decl(_req)//定义一个分析端口，名字是 _req，用于接收请求 TLP。`uvm_analysis_imp_decl是一个宏，用于声明一个分析端口的实现类。
  `uvm_analysis_imp_decl(_cpl)// 定义一个分析端口，名字是 _cpl，用于接收完成 TLP。`uvm_analysis_imp_decl是一个宏，用于声明一个分析端口的实现类。
  // -------- seq_item（一个TLP） --------
  class pcie_seq_item extends uvm_sequence_item;//这个class 是一个 UVM 序列项类，继承自 uvm_sequence_item。它表示一个 PCIe 事务（TLP），包含了 TLP 的各种字段，如类型、地址、长度、标签和数据等。
    rand tlp_type_e     tlp_type;// 一个可随机化的枚举字段，表示 TLP 的事务类型，名字是 tlp_type。它的类型是之前定义的枚举类型 tlp_type_e。
    rand bit [63:0]     addr;//定义了一个可随机化的 64 位地址字段，表示 TLP 的目标地址。这个字段的名字是 addr。
    rand bit [9:0]      len_dw;// 定义了一个可随机化的 10 位长度字段，表示 TLP 的传输长度，以 DW（双字）为单位。这个字段的名字是 len_dw。
    rand bit [7:0]      tag;// 定义了一个可随机化的 8 位标签字段，表示 TLP 的标签。这个字段的名字是 tag。
    rand bit [31:0]     data;   // 定义了一个可随机化的 32 位数据字段，表示 TLP 的数据。这个字段的名字是 data。
    bit                 retrain_toggle; // [LTSSM-ADD] 由序列控制是否在该事务前触发一次重训练，默认 0

    `uvm_object_utils_begin(pcie_seq_item)// 注册 pcie_seq_item 类为 UVM 对象，`uvm_object_utils_begin 是一个宏，用于注册 UVM 对象类，使其可以在 UVM 环境中使用。
      `uvm_field_enum(tlp_type_e, tlp_type, UVM_ALL_ON)// 注册 tlp_type 字段为枚举类型 tlp_type_e，UVM_ALL_ON 表示该字段在所有阶段都可用。`uvm_field_enum 是一个宏，用于注册枚举类型字段。
      `uvm_field_int(addr,  UVM_ALL_ON)// 注册 addr 字段为 64 位整数，UVM_ALL_ON 表示该字段在所有阶段都可用。`uvm_field_int 是一个宏，用于注册整数类型字段。
      `uvm_field_int(len_dw,UVM_ALL_ON)// 注册 len_dw 字段为 10 位整数，UVM_ALL_ON 表示该字段在所有阶段都可用。
      `uvm_field_int(tag,   UVM_ALL_ON)// 注册 tag 字段为 8 位整数，UVM_ALL_ON 表示该字段在所有阶段都可用。
      `uvm_field_int(data,  UVM_ALL_ON)// 注册 data 字段为 32 位整数，UVM_ALL_ON 表示该字段在所有阶段都可用。
      `uvm_field_int(retrain_toggle, UVM_BIN) // [LTSSM-ADD]
    `uvm_object_utils_end// 完成注册

    function new(string name="pcie_seq_item"); // 构造函数，接受一个可选的字符串参数 name，默认为 "pcie_seq_item"
      super.new(name); // 调用父类的构造函数，传入 name 参数。
      retrain_toggle = 1'b0; // [LTSSM-ADD] 缺省不触发重训练
    endfunction// 构造函数结束
    constraint c_len {// 定义一个约束 c_len，用于限制 len_dw 的取值范围。被引用在 pcie_if.sv 中的 covergroup cg_req 的 cp_len 覆盖点。
      len_dw inside {1,2,4,8,16};// 限制 len_dw 的取值范围为 1, 2, 4, 8, 16, 32, 64
       } // 限制 len_dw 的取值范围为 1 到 4
  endclass

  // ------------------------------------------------------------
  // 覆盖率采集组件：pcie_coverage
  // 放在包里，外部用 pcie_pkg::pcie_coverage 即可引用
  // ------------------------------------------------------------
  class pcie_coverage extends uvm_component;
    `uvm_component_utils(pcie_coverage)//

    // 从 monitor/scoreboard 接事务
    uvm_analysis_imp_req #(pcie_seq_item, pcie_coverage) imp_req;// 定义一个分析端口 imp_req，用于接收请求 TLP。uvm_analysis_imp_req 是一个宏，用于声明一个分析端口的实现类。
    uvm_analysis_imp_cpl #(pcie_seq_item, pcie_coverage) imp_cpl;// 定义一个分析端口 imp_cpl，用于接收完成 TLP。uvm_analysis_imp_cpl 是一个宏，用于声明一个分析端口的实现类。

    // 是否对完成包也采样（可关）
    bit enabled_cpl_cov = 1;//为 1 时，对 Cpl 方向也采样；为 0 时只采 req 侧。这个开关在 write_cpl() 里用到。

    // ---- 覆盖：请求 TLP ----
    covergroup cg_req with function sample(pcie_seq_item tr);//定义一个 covergroup，名字 cg_req。with function sample(pcie_seq_item tr)：表示不是自动触发，而是显式调用 cg_req.sample(tr) 时才采样
      option.per_instance = 1;//每个实例独立统计覆盖率

      // 1) 类型
      cp_type : coverpoint tr.tlp_type {// 定义一个覆盖点 cp_type，采样 tr.tlp_type 信号。
        bins MRd   = {TLP_MRd};// 在 cp_type 下面建立一个名为 MRd 的 bin，取值集合是枚举常量 TLP_MRd。当 tr.tlp_type == TLP_MRd 且此时发生了 sample，这个 bin 的命中数 +1
        bins MWr   = {TLP_MWr};
        bins CfgRd = {TLP_CfgRd};
        bins CfgWr = {TLP_CfgWr};
      }

      // 2) 长度（DW）
      cp_len : coverpoint tr.len_dw iff (tr.len_dw != 0){// 定义一个覆盖点 cp_len，采样 tr.len_dw 信号，但仅当 tr.len_dw 不为 0 时才采样
        bins len_1      = {1};
        bins len_2_4    = {[2:4]};
        bins len_5_8    = {[5:8]};
        bins len_9_16   = {[9:16]};
        //bins len_17_64  = {[17:64]};
        //bins len_65_256 = {[65:256]};
        ignore_bins len_gt16 = {[17:1023]};
        //illegal_bins len_huge   = {[257:$]};
      }

      // 3) 地址范围（按你目前设计先粗分；之后可替换为 BAR/窗口）
      cp_addr_rng : coverpoint tr.addr[31:0] {// 定义一个覆盖点 cp_addr_rng，采样 tr.addr 的低 32 位
        bins R_LOW   = {[32'h0000_0000 : 32'h0000_FFFF]};
        bins R_MID   = {[32'h0001_0000 : 32'h000F_FFFF]};
        bins R_HIGH  = {[32'h0010_0000 : 32'h0FFF_FFFF]};
        bins R_MMIOH = {[32'h1000_0000 : 32'hFFFF_FFFF]};
      }

      // 交叉
      x_type_len  : cross cp_type, cp_len{// 定义一个交叉覆盖点 x_type_len，交叉采样 cp_type 和 cp_len
      // CfgRd/CfgWr 只允许 L1，其他长度忽略
        ignore_bins cfg_len_invalid =// 如果 cp_type 为 CfgRd 或者 CfgWr，且 cp_len 为 [2:4] 或者 [5:8] 或者 [9:16]的时候，忽略
          binsof(cp_type) intersect {TLP_CfgRd, TLP_CfgWr} &&
          binsof(cp_len)  intersect {[2:4], [5:8], [9:16]};
          //ignore_bins len_gt16_cross = binsof(cp_len) intersect {[17:256]};
      }
      x_type_addr : cross cp_type, cp_addr_rng;// 定义一个交叉覆盖点 x_type_addr，交叉采样 cp_type 和 cp_addr_rng
    endgroup

    // ---- 覆盖：完成包（示例）----
    covergroup cg_cpl with function sample(pcie_seq_item tr);// 定义一个 covergroup，名字 cg_cpl。with function sample(pcie_seq_item tr)：表示不是自动触发，而是显式调用 cg_cpl.sample(tr) 时才采样
      option.per_instance = 1;// 每个实例独立统计覆盖率
      cp_cpl_tag : coverpoint tr.tag {// 定义一个覆盖点 cp_cpl_tag，采样 tr.tag 信号。
        bins tags[] = {[0:63]};             // 只统计 0..63
        ignore_bins above63 = {[64:255]};   // 其他忽略
      }
    endgroup

    // 构造
    function new(string name="pcie_coverage", uvm_component parent=null);
      super.new(name, parent);
      imp_req = new("imp_req", this);
      imp_cpl = new("imp_cpl", this);
      cg_req = new();
      cg_cpl = new();
    endfunction

    // analysis_imp 回调
    function void write_req(pcie_seq_item tr);// 当分析端口 imp_req 接收到一个 pcie_seq_item 时调用
      cg_req.sample(tr);// 采样 cg_req，记录当前请求 TLP 的覆盖信息
    endfunction

    function void write_cpl(pcie_seq_item tr);// 当分析端口 imp_cpl 接收到一个 pcie_seq_item 时调用
      if (enabled_cpl_cov) cg_cpl.sample(tr);// 如果 enabled_cpl_cov 为 1，则采样 cg_cpl，记录当前完成 TLP 的覆盖信息
    endfunction

    function void final_phase(uvm_phase phase);// 在 final 阶段打印覆盖率信息
      real cg  = cg_req.get_inst_coverage();//cg是 cg_req 的实例覆盖率，cg_req.get_inst_coverage() 返回 cg_req 的实例覆盖率。real cg 是一个实数类型，用于存储覆盖率百分比。get_inst_coverage() 方法返回当前覆盖组的实例覆盖率。
      real ct  = cg_req.cp_type.get_coverage();// ct 是 cp_type 的覆盖率，cg_req.cp_type.get_coverage() 返回 cp_type 的覆盖率。get_coverage() 方法返回当前覆盖点的覆盖率百分比。
      real cl  = cg_req.cp_len.get_coverage();// cl 是 cp_len 的覆盖率，cg_req.cp_len.get_coverage() 返回 cp_len 的覆盖率。
      real ca  = cg_req.cp_addr_rng.get_coverage();// ca 是 cp_addr_rng 的覆盖率，cg_req.cp_addr_rng.get_coverage() 返回 cp_addr_rng 的覆盖率。
      real cx1 = cg_req.x_type_len.get_coverage();// cx1 是 cg_req.x_type_len 的覆盖率，cg_req.x_type_len.get_coverage() 返回 cg_req.x_type_len 的覆盖率。
      real cx2 = cg_req.x_type_addr.get_coverage();// cx2 是 cg_req.x_type_addr 的覆盖率，cg_req.x_type_addr.get_coverage() 返回 cg_req.x_type_addr 的覆盖率。
      real cpl = cg_cpl.get_inst_coverage();// cpl 是 cg_cpl 的实例覆盖率，cg_cpl.get_inst_coverage() 返回 cg_cpl 的实例覆盖率。
      `uvm_info("COV",// 打印覆盖率信息
        $sformatf("REQ_CG=%.1f%%  (type=%.1f%%, len=%.1f%%, addr=%.1f%%, x_type_len=%.1f%%, x_type_addr=%.1f%%)  |  CPL_CG=%.1f%%",
                  cg, ct, cl, ca, cx1, cx2, cpl),// 使用 $sformatf 格式化字符串，输出覆盖率信息
        UVM_NONE)// UVM_NONE 表示没有特定的日志级别，这里使用默认级别
    endfunction

  endclass

  // -------- sequencer --------
  class pcie_sequencer extends uvm_sequencer #(pcie_seq_item);// 定义一个 sequencer 类 pcie_sequencer，继承自 uvm_sequencer，模板参数为 pcie_seq_item。
    `uvm_component_utils(pcie_sequencer)// 注册 pcie_sequencer 类
    function new(string n, uvm_component p);// 构造函数，接受一个字符串参数 n 和一个 uvm_component p
      super.new(n,p);// 调用父类的构造函数，传入 n 和 p 参数。
    endfunction
  endclass//这个类用于处理 PCIe 事务的序列项，继承自 UVM 的 uvm_sequencer 类。

  // -------- driver：把 item 映射到 pcie_if --------
  class pcie_driver extends uvm_driver #(pcie_seq_item);//这个driver实现了 PCIe 事务的驱动功能，把 pcie_seq_item 转换为 pcie_if 接口的信号，并驱动它们。task drive_req(pcie_seq_item tr) 是驱动的核心任务，将 pcie_seq_item 转换为 pcie_if 接口的信号，并驱动它们。
    `uvm_component_utils(pcie_driver)// 注册 pcie_driver 类
    virtual pcie_if vif;// 声明一个虚拟接口 vif，用于驱动 pcie_if 接口

    //bit sva_injected_once = 0; // [ADD] 标记：只触发一次违规

    function new(string n, uvm_component p);//这个function的功能是构造函数，接受一个字符串参数 n 和一个 uvm_component p。
      super.new(n,p);//
    endfunction

    function void build_phase(uvm_phase phase);//这个function的功能是在构建阶段获取虚拟接口 vif 的句柄。
      super.build_phase(phase);
      if(!uvm_config_db#(virtual pcie_if)::get(this, "", "vif", vif))// 从配置数据库获取虚拟接口 vif
        `uvm_fatal("NOVIF","pcie_if not set")// 如果没有设置 vif，则报错
    endfunction

  task drive_req(pcie_seq_item tr);// 任务 drive_req 的功能是将 pcie_seq_item 转换为 pcie_if 接口的信号，并驱动它们。
    // [LTSSM-ADD] 先处理 LTSSM：必要时触发一次重训练，并等链路可用
    @(posedge vif.clk);
    if (tr.retrain_toggle) begin
      `uvm_info(get_type_name(), "Inject retrain before TX", UVM_MEDIUM)
      fork vif.do_retrain(5); join_none
    end
      // 等链路进入可收发窗口
      wait (vif.link_up && !vif.link_retrain);
    //bit entered_wait;
    //entered_wait = 0;
    // 先准备好字段
    @(negedge vif.clk);//在这一拍对以下信号赋值，确保在 negedge 时信号稳定
    vif.req_type <= tlp_type_e'(tr.tlp_type);// 将 tr.tlp_type 转换为 tlp_type_e 枚举类型，。'是 SystemVerilog 中的类型转换运算符，用于将一个值转换为指定的类型。传给了 vif.req_type 信号。
    vif.req_addr <= tr.addr[31:0];// 将 tr.addr 的低 32 位赋值给 vif.req_addr 信号。
    vif.req_len  <= tr.len_dw;// 将 tr.len_dw 赋值给 vif.req_len 信号。
    vif.req_tag  <= tr.tag;// 将 tr.tag 赋值给 vif.req_tag 信号。
    vif.req_data <= tr.data;// 将 tr.data 赋值给 vif.req_data 信号。
    @(posedge vif.clk);      // 让地址先“稳定”满一个周期
    @(negedge vif.clk);     // 在 negedge 时开始握手
    vif.req_valid <= 1'b1;             // [CHANGED] 在 negedge 拉高


    do @(posedge vif.clk); while (!vif.req_ready);// 等待 req_ready 拉高

    @(negedge vif.clk);// 在 negedge 时完成握手
    vif.req_valid <= 1'b0;                      // 在 negedge 拉低，避免同拍采样竞态
    @(posedge vif.clk);
    // =========================
    // 关键：保证先进入等待期 (valid=1 && ready=0)
    // 策略：只在“观察到 ready==0 的 posedge”后，于随后的 negedge 拉高 valid；
    // 如果下一拍发现 ready==1，撤销这次尝试，继续等下一次 ready==0。
    // =========================
      // —— 确保进入等待期(valid=1 && ready=0)
      //do begin
        //@(posedge vif.clk);
        //if (vif.req_ready == 1'b0) begin
          //@(negedge vif.clk);
          //vif.req_valid <= 1'b1;
          //@(posedge vif.clk);
          //if (vif.req_valid && !vif.req_ready) entered_wait = 1;
          //else begin
            //@(negedge vif.clk);
            //vif.req_valid <= 1'b0;
          //end
        //end
      //end while (!entered_wait);

      //`ifndef NO_SVA_INJECT
  //`ifdef INJECT_VALID_DROP
      // 触发 a_req_valid_hold ：等待期把 valid 掉一下
      //@(negedge vif.clk);
      //vif.req_valid <= 1'b0;
      //`uvm_info(get_type_name(), $sformatf("SVA inject: drop valid during wait @%0t", $time), UVM_MEDIUM)
      //@(posedge vif.clk); @(posedge vif.clk);
      //@(negedge vif.clk);
      //vif.req_valid <= 1'b1; // 恢复，继续握手

  //`elsif INJECT_ADDR_TOGGLE
      // 触发 a_req_addr_stable ：等待期改地址
      //@(negedge vif.clk);
      //vif.req_addr <= vif.req_addr ^ 32'h1;
      //`uvm_info(get_type_name(), $sformatf("SVA inject: toggle addr during wait @%0t", $time), UVM_MEDIUM)
      //@(posedge vif.clk); @(posedge vif.clk);

  //`elsif INJECT_DATA_TOGGLE
      // 触发 a_req_data_stable ：等待期改数据
      //@(negedge vif.clk);
      //vif.req_data <= ~vif.req_data;
      //`uvm_info(get_type_name(), $sformatf("SVA inject: toggle data during wait @%0t", $time), UVM_MEDIUM)
      //@(posedge vif.clk); @(posedge vif.clk);

  //`elsif INJECT_TYPE_TOGGLE
      // 触发 a_req_type_stable ：等待期改 TLP 类型
      //@(negedge vif.clk);
      //vif.req_type <= (vif.req_type==TLP_MWr) ? TLP_MRd : TLP_MWr;
      //`uvm_info(get_type_name(), $sformatf("SVA inject: toggle type during wait @%0t", $time), UVM_MEDIUM)
      //@(posedge vif.clk); @(posedge vif.clk);

  //`else
      // 没开具体注入宏时，默认做地址变动违例（也可以改成不注入）
      //@(negedge vif.clk);
      //vif.req_addr <= vif.req_addr ^ 32'h1;
      //`uvm_info(get_type_name(), $sformatf("SVA inject: toggle addr during wait (default) @%0t", $time), UVM_MEDIUM)
      //@(posedge vif.clk); @(posedge vif.clk);
  //`endif
//`endif

      // 正常完成握手

    endtask

    task run_phase(uvm_phase phase);
      vif.drive_defaults();                // 初始化接口默认值
      vif.set_link_up(1'b1);               //  [ADDED] 显式拉起链路，避免刚开跑被断言拦住
      forever begin
        pcie_seq_item tr;
        seq_item_port.get_next_item(tr);
        drive_req(tr);
        seq_item_port.item_done();
      end
    endtask
  endclass

  // -------- monitor：采 REQ/CPL 两个方向 --------
  class pcie_monitor extends uvm_monitor;
    `uvm_component_utils(pcie_monitor)// 注册 pcie_monitor 类
    virtual pcie_if vif;// 声明一个虚拟接口 vif，用于监控 pcie_if 接口
    uvm_analysis_port #(pcie_seq_item) ap_req; //定义了一个分析端口 ap_req，用于发送请求 TLP。uvm_analysis_port 是 UVM 中的一个类，用于定义分析端口。
    uvm_analysis_port #(pcie_seq_item) ap_cpl; // 定义了一个分析端口 ap_cpl，用于发送完成 TLP。
    function new(string n, uvm_component p);
      super.new(n,p);// 调用父类构造函数
      ap_req = new("ap_req", this); // 创建请求分析端口
      ap_cpl = new("ap_cpl", this);// 创建完成分析端口
    endfunction
    function void build_phase(uvm_phase phase);
      if(!uvm_config_db#(virtual pcie_if)::get(this, "", "vif", vif))// 从配置数据库获取虚拟接口 vif
        `uvm_fatal("NOVIF","pcie_if not set")// 如果没有设置 vif，则报错
    endfunction
    task run_phase(uvm_phase phase);//在每个时钟上升沿看握手，一旦发现某个方向 valid&&ready，就把那一拍的字段采下来、拼成一个 pcie_seq_item，然后通过 analysis_port（ap_req/ap_cpl）广播给 scoreboard、coverage 等订阅者。
      bit req_hs, cpl_hs;      // 变量提前声明
      bit req_hs_d, cpl_hs_d;  // 上一拍握手状态

      forever begin//
        @(posedge vif.clk);//
        req_hs = (vif.req_valid && vif.req_ready);
        if (req_hs && !req_hs_d) begin//
          pcie_seq_item tr = pcie_seq_item::type_id::create("req_tr");// 创建一个新的 pcie_seq_item 对象
          tr.tlp_type  = tlp_type_e'(vif.req_type);// 把事务类型转换为枚举类型
          tr.addr  = vif.req_addr;
          tr.len_dw= vif.req_len;
          tr.tag   = vif.req_tag;
          tr.data  = vif.req_data;
          `uvm_info("MON", $sformatf("CAP %s addr=0x%0h tag=%0d data=0x%08h",
             (tr.tlp_type==TLP_MWr)?"MWr":"MRd",
             tr.addr, tr.tag, tr.data), UVM_MEDIUM)
          ap_req.write(tr);
        end
        req_hs_d = req_hs;

        // --- 完成方向（CplD：同样只在握手沿采一次） ---
        cpl_hs = (vif.cpl_valid && vif.cpl_ready);
        if (cpl_hs && !cpl_hs_d) begin//
          pcie_seq_item c = pcie_seq_item::type_id::create("cpl_tr");
          c.tlp_type = TLP_MRd; // 用于比对；读的CplD
          c.tag  = vif.cpl_tag;
          c.data = vif.cpl_data;
          `uvm_info("MON", $sformatf("CAP CplD tag=%0d data=0x%08h",
                c.tag, c.data), UVM_MEDIUM)
          ap_cpl.write(c);
        end
        cpl_hs_d = cpl_hs;
      end
    endtask
  endclass

  // -------- agent --------
  class pcie_agent extends uvm_agent;
    `uvm_component_utils(pcie_agent)
    pcie_sequencer sqr; // 声明一个 pcie_sequencer 对象 sqr，用于发送事务
    pcie_driver drv; // 声明一个 pcie_driver 对象 drv，用于驱动 pcie_if 接口
    pcie_monitor mon;// 声明一个 pcie_monitor 对象 mon，用于监控 pcie_if 接口
    function new(string n, uvm_component p); 
      super.new(n,p); 
    endfunction
    function void build_phase(uvm_phase phase);
      sqr = pcie_sequencer::type_id::create("sqr", this);// 创建一个 pcie_sequencer 实例 sqr
      drv = pcie_driver   ::type_id::create("drv", this);// 创建一个 pcie_driver 实例 drv
      mon = pcie_monitor  ::type_id::create("mon", this);// 创建一个 pcie_monitor 实例 mon
    endfunction
    function void connect_phase(uvm_phase phase);
      drv.seq_item_port.connect(sqr.seq_item_export);// 连接驱动的 seq_item_port 到 sequencer 的 seq_item_export
    endfunction
  endclass

  // -------- scoreboard（最小版：按 tag 匹配 MRd 的CPLD） --------
  class pcie_scoreboard extends uvm_component;
    `uvm_component_utils(pcie_scoreboard)// 注册 pcie_scoreboard 类
    uvm_analysis_imp_req #(pcie_seq_item, pcie_scoreboard) imp_req;// 分析端口实现：用于接收请求 TLP
    uvm_analysis_imp_cpl #(pcie_seq_item, pcie_scoreboard) imp_cpl;// 分析端口实现：用于接收完成 TLP
    // 记录 outstanding 读：tag -> addr
    bit [63:0] tag2addr [byte]; // 声明一个关联数组，用于存储 tag 到 addr 的映射关系
    function new(string n, uvm_component p); 
      super.new(n,p);
      imp_req = new("imp_req", this);// 创建请求分析端口实现
      imp_cpl = new("imp_cpl", this);// 创建完成分析端口实现
    endfunction
    // 接口：analysis_imp 需要 write()
    function void write_req(input pcie_seq_item tr);//定义 write_req 函数，用于写入请求
      if (tr.tlp_type==TLP_MRd)// 如果事务类型是 MRd
      tag2addr[tr.tag] = tr.addr;// 将 tag 和 addr 添加到 tag2addr 关联数组中
    endfunction
    //  不在表里的完成 => 视为非 MRd（Cfg/其他），忽略而不是报错
    function void write_cpl(pcie_seq_item c);
      if (!tag2addr.exists(c.tag)) begin
        `uvm_info("SB",
          $sformatf("Ignore non-MRd/unsolicited CPL tag=%0d data=0x%08h",
                    c.tag, c.data),
          UVM_LOW)
        return; //  直接返回，不报 UVM_ERROR
      end
      `uvm_info("SB",
        $sformatf("CPL matched tag=%0d addr=0x%0h data=0x%08h",
                  c.tag, tag2addr[c.tag], c.data),
        UVM_MEDIUM)
      tag2addr.delete(c.tag);
    endfunction

  endclass

  // -------- env --------
  class pcie_env extends uvm_env;
    `uvm_component_utils(pcie_env)// 注册 pcie_env 类
    pcie_agent agt;// 声明一个 pcie_agent 对象 agt，用于处理 PCIe 事务
    pcie_scoreboard sb;// 声明一个 pcie_scoreboard 对象 sb，用于验证事务class pcie_seq_item
    pcie_coverage   cov; 
    function new(string n, uvm_component p);
       super.new(n,p);
    endfunction
    function void build_phase(uvm_phase phase);// 构建阶段：创建 agent 和 scoreboard
      agt = pcie_agent     ::type_id::create("agt", this);// 创建一个 pcie_agent 实例 agt
      sb  = pcie_scoreboard::type_id::create("sb",  this);// 创建一个 pcie_scoreboard 实例 sb
      cov   = pcie_coverage  ::type_id::create("cov", this);
    endfunction
    function void connect_phase(uvm_phase phase);// 连接阶段：将 agent 的分析端口连接到 scoreboard
      agt.mon.ap_req.connect(sb.imp_req);// 将 agent 的请求分析端口连接到 scoreboard 的请求端口实现
      agt.mon.ap_req.connect(cov.imp_req);// 将 agent 的请求分析端口连接到覆盖率的请求端口实现
      agt.mon.ap_cpl.connect(sb.imp_cpl);// 将 agent 的完成分析端口连接到 scoreboard 的完成端口实现
      agt.mon.ap_cpl.connect(cov.imp_cpl);// 将 agent 的完成分析端口连接到覆盖率的完成端口实现
    endfunction
  endclass

  // -------- sequence（冒烟：先写后读） --------
  class pcie_smoke_seq extends uvm_sequence #(pcie_seq_item);// 冒烟测试序列：先写后读。这个class的功能是：发送一组事务，包括写和读，然后检查结果
    `uvm_object_utils(pcie_smoke_seq)// 注册 pcie_smoke_seq 类
    function new(string n="pcie_smoke_seq"); 
      super.new(n); 
    endfunction
    task body();// 序列主体：发送一组事务
      pcie_seq_item tr;// 声明一个 pcie_seq_item 对象
      // 写：MWr addr=0x10 data=0xA5A50001
      tr = pcie_seq_item::type_id::create("wr");// 创建一个新的 pcie_seq_item 对象
      start_item(tr);// 开始事务
        tr.tlp_type   = TLP_MWr; // 设置事务类型为 MWr
        tr.addr = 'h10; // 设置地址为 0x10
        tr.len_dw=1; // 设置传输长度为 1 DW
        tr.data='hA5A5_0001; // 设置数据为 0xA5A50001
        tr.tag=8'h00;// 设置标签为 0
        tr.retrain_toggle = 1'b0; // [LTSSM-ADD] 冒烟默认不触发重训练
      finish_item(tr);// 完成事务
      `uvm_info("SEQ", $sformatf("SEND MWr addr=0x%0h data=0x%08h tag=%0d",
             tr.addr, tr.data, tr.tag), UVM_MEDIUM)// 打印信息
      // 读：MRd addr=0x10 tag=7
      tr = pcie_seq_item::type_id::create("rd");// 创建一个新的 pcie_seq_item 对象
      start_item(tr);// 开始事务
        tr.tlp_type   = TLP_MRd; // 设置事务类型为 MRd
        tr.addr = 'h10;// 设置地址为 0x10
        tr.len_dw=1; // 设置传输长度为 1 DW
        tr.tag=8'h07;// 设置标签为 7
        tr.retrain_toggle = 1'b0; // [LTSSM-ADD]
      finish_item(tr);// 完成事务
      `uvm_info("SEQ", $sformatf("SEND MRd addr=0x%0h tag=%0d",
             tr.addr, tr.tag), UVM_MEDIUM)// 打印信息
    endtask
  endclass

  // ===================================================================
  // [ADDED] 覆盖拉升：扫网格 sequence（类型×长度×对齐/边界）
  // ===================================================================
  class pcie_cov_sweep_seq extends uvm_sequence #(pcie_seq_item);//这个class的功能是：发送一组事务，包括写和读，然后检查结果。特点是：类型，长度，对齐/边界
    `uvm_object_utils(pcie_cov_sweep_seq)
    function new(string name="pcie_cov_sweep_seq"); super.new(name); endfunction

  task body();
    int lens[] = '{1,2,4,8,16};// 定义长度数组：1, 2, 4, 8, 16, 32, 64 DW
    tlp_type_e reqs[] = '{TLP_MRd,TLP_MWr,TLP_CfgRd,TLP_CfgWr};// 定义请求类型数组：内存读、内存写、配置读和配置写。tlp_type_e 是一个枚举类型，表示 TLP 的事务类型

    bit [31:0] base_addr[4] = '{// 定义 base_addr 数组，表示四个大区间。base_addr[0] 表示 LOW，base_addr[1] 表示 MID，base_addr[2] 表示 HIGH，base_addr[3] 表示 MMIOH
      32'h0000_0010, // LOW
      32'h0002_0000, // MID
      32'h0100_0000, // HIGH
      32'h9000_0000  // MMIOH
    };

    foreach (reqs[i])// 遍历请求类型数组
      foreach (lens[j])// 遍历长度，长度指的是传输长度，被定义在 lens 数组
        foreach (base_addr[b])// 遍历 base_addr
          for (int k = 0; k < 2; k++) begin// 遍历对齐/不对齐
            pcie_seq_item tr = pcie_seq_item::type_id::create($sformatf("t_%0d_%0d_%0d_%0d", i,j,b,k));// 创建一个新的 pcie_seq_item 对象，名字格式为 t_i_j_b_k。tr是一个 pcie_seq_item 对象，用于表示一个 PCIE 事务
            start_item(tr);//UVM 的 sequence ↔ driver 握手，告诉 driver“我要发一个 item 了，等我填好字段”。
            assert(tr.randomize() with {// 对 tr 进行随机化
              tlp_type == reqs[i];// 事务类型等于请求类型数组中的第 i 个元素
              !(tlp_type inside {TLP_CfgRd, TLP_CfgWr}) -> (len_dw == lens[j]);// 如果事务类型不是配置读或配置写，则传输长度等于长度数组中的第 j 个元素。->表示条件，表示只有在事务类型不是配置读或配置写时，传输长度等于长度数组中的第 j 个元素
              (tlp_type inside {TLP_CfgRd, TLP_CfgWr})   -> (len_dw == 10'd1);// 如果事务类型是配置读或配置写，则传输长度等于 1
              // 以 base_addr[b] 为基准，做对齐/不对齐 + 贴4KB边界
              addr[31:12] == base_addr[b][31:12];// 地址的高 12 位等于 base_addr[b] 的高 12 位
              (j%2==0) -> (addr[1:0] == 2'b00);// 如果 j 为偶数，则地址的低 2 位等于 00
              (j%2==1) -> (addr[1:0] inside {[2'b01:2'b11]});// 如果 j 为奇数，则地址的低 2 位在 01 到 11 之间。->表示条件，表示只有在 j 为奇数时，地址的低 2 位在 01 到 11 之间
              (k==0)   -> (addr[11:0] inside {[12'h000:12'h00F]});// 如果 k 为 0，则地址的低 12 位在 000 到 00F 之间
              (k==1)   -> (addr[11:0] inside {[12'hFF0:12'hFFF]});// 如果 k 为 1，则地址的低 12 位在 FF0 到 FFF 之间

              tag inside {[0:15]};// 标签在 0 到 15 之间，tag 用于标识事务
            });//这段代码定义了一个 pcie_seq_item 对象 tr 的随机化条件，包括事务类型、传输长度、地址、标签等。
            // [LTSSM-ADD] 覆盖扫网格默认不触发重训练
            tr.retrain_toggle = 1'b0;
            finish_item(tr);

            if (tr.tlp_type == TLP_MWr) begin// 如果事务类型是内存写
              pcie_seq_item rd = pcie_seq_item::type_id::create($sformatf("rd_after_wr_%0d_%0d_%0d_%0d", i,j,b,k));// 创建一个新的 pcie_seq_item 对象，名字格式为 rd_after_wr_i_j_b_k。rd是一个 pcie_seq_item 对象，用于表示一个 PCIE 内存读事务
              start_item(rd);// 开始内存读事务
              assert(rd.randomize() with { tlp_type==TLP_MRd; addr==tr.addr; len_dw==tr.len_dw; tag inside {[0:15]}; });// 对 rd 进行随机化，确保事务类型是内存读，地址、传输长度、标签等字段与 tr 一致
              rd.retrain_toggle = 1'b0; // [LTSSM-ADD]
              finish_item(rd);
            end
          end
  endtask  

  endclass
  // ===================================================================
  // [ADDED] 覆盖拉升：洞填充 sequence（未命中 bins / B2B / outstanding）
  // ===================================================================
  class pcie_cov_holes_seq extends uvm_sequence #(pcie_seq_item);
    `uvm_object_utils(pcie_cov_holes_seq)
    function new(string name="pcie_cov_holes_seq"); super.new(name); endfunction

    task body();
      pcie_seq_item tr;// 声明一个 pcie_seq_item 对象

      // 洞1：CfgWr + 不对齐 + L1
      tr = pcie_seq_item::type_id::create("cfgwr_unaligned_L1");// 创建一个新的 pcie_seq_item 对象，名字为 cfgwr_unaligned_L1
      start_item(tr);// 开始事务
      assert(tr.randomize() with {// 对 tr 进行随机化。assert 语句用于检查 tr 的随机化条件是否满足，如果满足则执行后面的语句，否则报错
        tlp_type == TLP_CfgWr;//检查事务类型是否等于 TLP_CfgWr
        len_dw   == 1;//检查传输长度是否等于 1
        addr[1:0] inside {[2'b01:2'b11]};//检查地址的低 2 位是否在 01 到 11 之间
      });
      tr.retrain_toggle = 1'b0; // [LTSSM-ADD]
      finish_item(tr);// 完成事务

      // 洞2：MRd L16 紧贴 4KB 高端
      tr = pcie_seq_item::type_id::create("mrd_L16_near_4k");// 创建一个新的 pcie_seq_item 对象，名字为 mrd_L16_near_4k
      start_item(tr);// 开始事务
      assert(tr.randomize() with {// 对 tr 进行随机化
        tlp_type == TLP_MRd;//当事务类型等于 TLP_MRd 时
        len_dw   == 16;//当传输长度等于 16 时
        addr[11:0] inside {[12'hFF0:12'hFFF]};//当地址的低 12 位在 FF0 到 FFF 之间时
      });
      tr.retrain_toggle = 1'b0; // [LTSSM-ADD]
      finish_item(tr);

      // 洞3：MWr 连发 8 次（back-to-back / outstanding）
      for (int i=0; i<8; i++) begin// 遍历 8 次
        tr = pcie_seq_item::type_id::create($sformatf("mwr_b2b_%0d", i));// 创建一个新的 pcie_seq_item 对象，名字格式为 mwr_b2b_i
        start_item(tr);
        assert(tr.randomize() with {
          tlp_type == TLP_MWr;//事务类型为 TLP_MWr
          len_dw   inside {4,8};//传输长度为 4 或 8
          addr[1:0] == 2'b00;//地址的低 2 位为 00
        });
        tr.retrain_toggle = 1'b0; // [LTSSM-ADD]
        finish_item(tr);
      end
    endtask
  endclass

  // 生成大量 MRd（覆盖 tag 段、长度段），快速拉高 CPL_CG
  class pcie_cpl_tag_spray_seq extends uvm_sequence #(pcie_seq_item);
    `uvm_object_utils(pcie_cpl_tag_spray_seq)
    function new(string name="pcie_cpl_tag_spray_seq"); super.new(name); endfunction

    task body();
      // 你 DUT 能稳定返回的地址：若 0x10 有返回（dead_beef），就固定用 0x10
      bit [63:0] base = 64'h10;// 基础地址，默认为 0x10

      // 覆盖 tag 0..63（或 0..255，如果 DUT 支持并发更大）
      for (int t = 0; t < 64; t++) begin// 遍历 0..63
        pcie_seq_item rd = pcie_seq_item::type_id::create($sformatf("spray_rd_%0d", t));// 创建一个新的 pcie_seq_item 对象，名字格式为 spray_rd_t
        start_item(rd);
        assert(rd.randomize() with {
          tlp_type == TLP_MRd;
          addr     == base;
          len_dw   inside {1,2,4,8,16};
          tag      == t[7:0];
        });
        rd.retrain_toggle = 1'b0; // [LTSSM-ADD]
        finish_item(rd);
      end
    endtask
  endclass

  class pcie_msi_ping_seq extends uvm_sequence #(pcie_seq_item);
    `uvm_object_utils(pcie_msi_ping_seq)
    function new(string n="pcie_msi_ping_seq"); super.new(n); endfunction
    task body();
      pcie_seq_item tr = pcie_seq_item::type_id::create("msi");
      start_item(tr);
      assert(tr.randomize() with {
        tlp_type == TLP_MWr;                 // 🟧 [ADDED] MSI 本质是 MWr
        addr     == MSI_ADDR[63:0];          // 🟧 [ADDED] 门铃地址
        len_dw   == 1;
        data     inside {[32'h40:32'h7F]};   // 🟧 [ADDED] 随便来个向量号
        tag      == 8'h00;                   // Posted，无需 Cpl
      });
      tr.retrain_toggle = 1'b0;
      finish_item(tr);
    endtask
  endclass


  // ===================================================================
  // [ADDED] 覆盖拉升用 test：串行跑 sweep -> holes
  // ===================================================================
  class pcie_cov_test extends uvm_test;
    `uvm_component_utils(pcie_cov_test)
    pcie_env env;

    function new(string n, uvm_component p); super.new(n,p); endfunction

    function void build_phase(uvm_phase phase);
      env = pcie_env::type_id::create("env", this);
    endfunction

  task run_phase(uvm_phase phase);
    pcie_cov_sweep_seq     sweep;//调用 pcie_cov_sweep_seq 类型的 sweep
    pcie_cpl_tag_spray_seq spray; // 调用 pcie_cpl_tag_spray_seq 类型的 spray
    pcie_cov_holes_seq     holes;//调用 pcie_cov_holes_seq 类型的 holes
    pcie_msi_ping_seq      msi;

    phase.raise_objection(this);// 申请阻塞

    // 先扫网格
    sweep = pcie_cov_sweep_seq::type_id::create("sweep");// 创建一个 pcie_cov_sweep_seq 对象，名字为 sweep
    sweep.start(env.agt.sqr);// 启动序列

    // 再喷 MRd 拉高 CPL 覆盖
    spray = pcie_cpl_tag_spray_seq::type_id::create("spray");// 创建一个 pcie_cpl_tag_spray_seq 对象，名字为 spray
    spray.start(env.agt.sqr);// 启动序列

    // 最后补洞
    holes = pcie_cov_holes_seq::type_id::create("holes");// 创建一个 pcie_cov_holes_seq 对象，名字为 holes
    holes.start(env.agt.sqr);// 启动序列

    msi = pcie_msi_ping_seq::type_id::create("msi"); //  [FIXED]
    msi.start(env.agt.sqr);                                            //  [ADDED]
    
    phase.drop_objection(this);// 结束测试，撤销异议
  endtask

  endclass


  // -------- test --------
  class pcie_base_test extends uvm_test;
    `uvm_component_utils(pcie_base_test)
    pcie_env env; // 声明一个 pcie_env 对象 env，用于环境配置
    function new(string n, uvm_component p); 
      super.new(n,p); 
    endfunction
    function void build_phase(uvm_phase phase);
      env = pcie_env::type_id::create("env", this);// 创建一个 pcie_env 实例 env
    endfunction
    task run_phase(uvm_phase phase);
      pcie_smoke_seq seq_h;// 声明一个 pcie_smoke_seq 对象 seq_h
      phase.raise_objection(this);
      
      seq_h = pcie_smoke_seq::type_id::create("seq_h");// 创建一个 pcie_smoke_seq 对象 seq_h
      seq_h.start(env.agt.sqr);// 启动序列 seq，发送事务到 sequencer
      #200ns;
      phase.drop_objection(this);// 结束测试，撤销异议
    endtask
  endclass

endpackage
`endif