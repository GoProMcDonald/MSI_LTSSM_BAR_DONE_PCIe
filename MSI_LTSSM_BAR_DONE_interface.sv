`include "pcie_pkg.sv"   // 临时兜底，确保 pcie_pkg 先被定义
//整个文件是一个 SystemVerilog 接口（interface），用于定义 PCIe 相关的信号和断言。always 在接口中定义了请求和完成的信号，以及相关的断言和覆盖率采样。
interface pcie_if #(parameter ADDR_W=32, DATA_W=32, LEN_W=10) (input logic clk, rst_n);//#( … )：参数列表，用来参数化接口里信号的位宽等。( … )：端口列表，把外部的 clk、rst_n 传进 interface，供里面的 SVA、covergroup 和任务使用

  import pcie_pkg::*;

  // ===== [LTSSM-ADD] 抽象链路信号（LTSSM 的效果） =====
  logic link_up;        // =1 代表处于 L0，可正常收发
  logic link_retrain;   // =1 表示“重训练/恢复”窗口，期间应停发/停收

  task automatic set_link_up(bit up);    //  [ADDED] 便于 test/driver 调用，不直接改信号
    link_up <= up;                       //  [ADDED]
  endtask                                 //  [ADDED]

  // 一键触发一次重训练：保持 N 拍
  task automatic do_retrain(int hold_cycles=10);
    link_retrain <= 1'b1;
    repeat(hold_cycles) @(posedge clk);
    link_retrain <= 1'b0;
  endtask
  // =====================================================
  
  // Request: MRd/MWr/Cfg*
  logic        req_valid, req_ready;//宽度为1，表示握手信号
  tlp_type_e  req_type;    // 事务类型，0:MRd 1:MWr 2:CfgRd 3:CfgWr（示例）tlp_type_e 是枚举类型，定义在 pcie_pkg.sv 中
  logic [ADDR_W-1:0] req_addr;// 低位地址，32位或64位。目标地址；在 valid && !ready 期间必须保持稳定
  logic [LEN_W-1:0]  req_len;     // 传输长度，以DW或字节计，统一即可。
  logic [7:0]        req_tag;     // MRd/Cfg* 用
  logic [DATA_W-1:0] req_data;    // 仅 MWr 有效

  // Completion: Cpl/CplD（读必有；写可选“验证友好”状态）
  logic        cpl_valid, cpl_ready;// 宽度为1，表示握手信号
  logic [2:0]  cpl_status;  // 完成状态，0=OK
  logic [7:0]  cpl_tag;// MRd/Cfg* 用
  logic [DATA_W-1:0] cpl_data;    // 仅 CplD 有

  // ---------- 默认驱动 ----------
  task automatic drive_defaults(bit accept_cpl = 1'b1);//drive_defaults 任务，接受一个可选参数 accept_cpl，默认为 1'b1
    req_valid <= 1'b0;
    req_type  <= TLP_MRd;      //TLP_MRd 是 pcie_pkg.sv 中定义的枚举类型
    req_addr  <= '0;
    req_len   <= '0;
    req_tag   <= '0;
    req_data  <= '0;
    req_ready <= 1'b0;

    cpl_ready <= accept_cpl;   // [ADDED]
    cpl_valid <= 1'b0;         // [ADDED]
    cpl_status<= '0;           // [ADDED]
    cpl_tag   <= '0;           // [ADDED]
    cpl_data  <= '0;           // [ADDED]

    // [LTSSM-ADD] 默认不在重训练窗口；link_up 是否拉高由 tb_top 或 driver 决定
    link_retrain <= 1'b0;
    link_up      <= 1'b1;
  endtask

  // ---------- SVA（握手稳定性） ----------
  `define DISABLE_IF disable iff(!rst_n)// 禁用断言和覆盖率，除非 rst_n 为 1
  // 在 valid=1 且 ready=0 的等待期，信号一旦变化就违规（同拍判定）
  property p_stable_during_wait(logic v, logic r, logic [$bits(req_data)-1:0] sig);//定义一个属性 p_stable_during_wait，参数包括 valid 信号 v、ready 信号 r 和要检查稳定性的信号 sig，其中 sig 的位宽由 req_data 的位宽决定
    @(posedge clk) `DISABLE_IF// 在时钟上升沿触发，DISABLE_IF 用于禁用断言和覆盖率，意思是除非 rst_n 为 1，否则不启用
      (v && !r) |-> $stable(sig) until_with r;// 当 valid=1 且 ready=0 时，sig 必须保持稳定，直到 ready=1
  endproperty

  // [CHANGED] valid 在等待期不能掉（之前写法矛盾导致永不触发）
  property p_no_drop_valid_while_wait(logic v, logic r);// 定义一个属性 p_no_drop_valid_while_wait，参数包括 valid 信号 v 和 ready 信号 r
    @(posedge clk) `DISABLE_IF// 在时钟上升沿触发，DISABLE_IF 用于禁用断言和覆盖率，意思是除非 rst_n 为 1，否则不启用
      (v && !r) |-> v until_with r;// 当 valid=1 且 ready=0 时，valid 必须保持为 1，直到 ready=1
  endproperty

    // === req 侧断言 ===
  a_req_valid_hold  : assert property (p_no_drop_valid_while_wait(req_valid, req_ready))//对 req_valid 和 req_ready 使用 p_no_drop_valid_while_wait 属性进行断言，a_req_valid_hold是一个断言名称
    else $fatal(1, "SVA a_req_valid_hold violated @%0t", $time);// 如果断言失败，打印错误信息并终止仿真

  a_req_type_stable : assert property (p_stable_during_wait(req_valid, req_ready, req_type))// 对 req_type 使用 p_stable_during_wait 属性进行断言
    else $fatal(1, "SVA a_req_type_stable violated @%0t", $time);// 如果断言失败，打印错误信息并终止仿真

  a_req_addr_stable : assert property (p_stable_during_wait(req_valid, req_ready, req_addr))// 对 req_addr 使用 p_stable_during_wait 属性进行断言
    else $fatal(1, "SVA a_req_addr_stable violated @%0t", $time);// 如果断言失败，打印错误信息并终止仿真

  a_req_len_stable  : assert property (p_stable_during_wait(req_valid, req_ready, req_len))// 对 req_len 使用 p_stable_during_wait 属性进行断言
    else $fatal(1, "SVA a_req_len_stable violated @%0t", $time);// 如果断言失败，打印错误信息并终止仿真

  a_req_tag_stable  : assert property (p_stable_during_wait(req_valid, req_ready, req_tag))// 对 req_tag 使用 p_stable_during_wait 属性进行断言
    else $fatal(1, "SVA a_req_tag_stable violated @%0t", $time);// 如果断言失败，打印错误信息并终止仿真

  a_req_data_stable : assert property (p_stable_during_wait(req_valid, req_ready, req_data))// 对 req_data 使用 p_stable_during_wait 属性进行断言
    else $fatal(1, "SVA a_req_data_stable violated @%0t", $time);// 如果断言失败，打印错误信息并终止仿真

  // === cpl 侧断言（如果也需要稳定性校验） ===
  a_cpl_valid_hold    : assert property (p_no_drop_valid_while_wait(cpl_valid, cpl_ready))
    else $fatal(1, "SVA a_cpl_valid_hold violated @%0t", $time);

  a_cpl_status_stable : assert property (p_stable_during_wait(cpl_valid, cpl_ready, cpl_status))
    else $fatal(1, "SVA a_cpl_status_stable violated @%0t", $time);

  a_cpl_tag_stable    : assert property (p_stable_during_wait(cpl_valid, cpl_ready, cpl_tag))
    else $fatal(1, "SVA a_cpl_tag_stable violated @%0t", $time);

  a_cpl_data_stable   : assert property (p_stable_during_wait(cpl_valid, cpl_ready, cpl_data))
    else $fatal(1, "SVA a_cpl_data_stable violated @%0t", $time);

  // ===== [LTSSM-ADD] 断言：链路未就绪/重训练期间禁止发/收 =====
  property p_no_tx_when_link_down;  @(posedge clk) `DISABLE_IF (!link_up)     |-> !req_valid; endproperty
  a_no_tx_linkdown  : assert property(p_no_tx_when_link_down);

  property p_no_tx_when_retrain;    @(posedge clk) `DISABLE_IF (link_retrain) |-> !req_valid; endproperty
  a_no_tx_retrain   : assert property(p_no_tx_when_retrain);

  property p_no_cpl_when_retrain;   @(posedge clk) `DISABLE_IF (link_retrain) |-> !cpl_valid; endproperty
  a_no_cpl_retrain  : assert property(p_no_cpl_when_retrain);
  // =====================================================

  // ---------- 覆盖 ----------
  //covergroup cg_tlp @(posedge clk);
    //coverpoint req_type {
      //bins rd={TLP_MRd}; bins wr={TLP_MWr}; bins cfg_rd={TLP_CfgRd}; bins cfg_wr={TLP_CfgWr};
    //}
    //coverpoint req_len  { bins len_small={[1:4]}; bins len_mid={[5:16]}; bins len_large={[17:64]}; }
    //cross req_type, req_len;
  //endgroup
  //cg_tlp cov = new();

  // ----------------------------- Functional Coverage -----------------------------
  // 只在“握手成功”的那个周期采样，避免虚假计数
  // 覆盖维度：类型 / 长度 / 对齐 / 4KB 边界 / tag，并做关键交叉
  covergroup cg_req;// 定义一个覆盖组 cg_req，采样请求侧的 TLP
    option.per_instance = 1;// 每个实例单独采样
    //覆盖组本身不自动工作，只有在采样时（调用 cg_req.sample()，或命中了你给它设置的 sample 事件）才会把当下观察到的信号/变量值记进各个 bin。
    cp_type : coverpoint req_type {// 定义一个覆盖点 cp_type，采样 req_type 信号。
      bins MRd   = {TLP_MRd};//在 cp_type 下面建立一个名为 MRd 的 bin，取值集合是枚举常量 TLP_MRd。当 req_type == TLP_MRd 且此时发生了 sample，这个 bin 的命中数 +1
      bins MWr   = {TLP_MWr};//当 req_type == TLP_MWr 时，命中 MWr bin
      bins CfgRd = {TLP_CfgRd};// 当 req_type == TLP_CfgRd 时，命中 CfgRd bin
      bins CfgWr = {TLP_CfgWr};// 当 req_type == TLP_CfgWr 时，命中 CfgWr bin
    }

    cp_len : coverpoint req_len iff (req_len != 0) {// 定义一个覆盖点 cp_len，采样 req_len 信号，但仅当 req_len 不为 0 时才采样
      bins L1  = {1};//当 req_len == 1 时，命中 L1 bin
      bins L2  = {2};// 当 req_len == 2 时，命中 L2 bin
      bins L4  = {4};// 当 req_len == 4 时，命中 L4 bin
      bins L8  = {8};// 当 req_len == 8 时，命中 L8 bin
      bins L16 = {16};// 当 req_len == 16 时，命中 L16 bin
      ignore_bins LEN_ZERO = {0};// 忽略 req_len == 0 的情况，因为我们只关心非零长度的 TLP
    }

    cp_align : coverpoint req_addr[1:0] {// 定义一个覆盖点 cp_align，采样 req_addr 的最低两位
      bins aligned   = {2'b00};// 当 req_addr 的最低两位为 00 时，命中 aligned bin
      bins unaligned = {[2'b01:2'b11]};// 当 req_addr 的最低两位为 01、10 或 11 时，命中 unaligned bin
    }

    cp_4k_near : coverpoint req_addr[11:0] {// 定义一个覆盖点 cp_4k_near，采样 req_addr 的低 12 位
      bins near_low  = {[12'h000:12'h00F]};//当 req_addr 在 0-15 范围内时，命中 near_low bin
      bins near_high = {[12'hFF0:12'hFFF]};// 当 req_addr 在 4096-4095 范围内时，命中 near_high bin
    }

    cp_tag : coverpoint req_tag {// 定义一个覆盖点 cp_tag，采样 req_tag 信号
      bins b_small = {[0:3]};//当 req_tag 在 0-3 范围内时，命中 b_small bin
      bins b_mid   = {[4:7]};// 当 req_tag 在 4-7 范围内时，命中 b_mid bin
      bins b_high  = {[8:15]}; // 当 req_tag 在 8-15 范围内时，命中 b_high bin
    }

    // 关键交叉：类型 × 长度 × 对齐
    cx_type_len_align : cross cp_type, cp_len, cp_align;// 定义一个交叉覆盖点 cx_type_len_align，交叉采样 cp_type、cp_len 和 cp_align
  endgroup

  // 完成包覆盖（状态/标签；如有 byte_count 信号，可在此增加对其覆盖）
  covergroup cg_cpl;// 定义一个覆盖组 cg_cpl，采样完成侧的 TLP
    option.per_instance = 1;// 每个实例单独采样
    cp_status : coverpoint cpl_status;// 定义一个覆盖点 cp_status，采样 cpl_status 信号
    cp_tag_c  : coverpoint cpl_tag {// 定义一个覆盖点 cp_tag_c，采样 cpl_tag 信号
      bins t0_15   = {[0:15]};// 当 cpl_tag 在 0-15 范围内时，命中 t0_15 bin
      bins t16_31  = {[16:31]};// 当 cpl_tag 在 16-31 范围内时，命中 t16_31 bin
      bins t32_63  = {[32:63]};// 当 cpl_tag 在 32-63 范围内时，命中 t32_63 bin
      // 如果你喷到了 0..63，就足够100%；没跑到更高 tag，不影响
      ignore_bins above63 = {[64:255]};// 忽略 cpl_tag 大于 63 的情况，因为我们只关心 0-63 范围内的 tag
    }
  endgroup

  // ===== [LTSSM-ADD] 覆盖：记录 link 事件 =====
  covergroup cg_link @(posedge clk);
    option.per_instance = 1;
    cp_up      : coverpoint link_up;
    cp_retrain : coverpoint link_retrain { bins pulse[] = (0=>1=>0); }
  endgroup

  cg_req u_cg_req = new();// 创建一个 cg_req 实例，用于采样请求侧的 TLP。u_cg_req 是 cg_req 的实例名
  cg_cpl u_cg_cpl = new();// 创建一个 cg_cpl 实例，用于采样完成侧的 TLP。u_cg_cpl 是 cg_cpl 的实例名
  cg_link u_cg_link = new();// [LTSSM-ADD] link 事件覆盖

  // 采样触发：握手成功
  always @(posedge clk) begin// 在时钟上升沿触发
    if (rst_n) begin// 如果 rst_n 为 1，表示系统正常运行
      if (req_valid && req_ready && (req_len != 0))// 如果 req_valid 和 req_ready 都为 1，且 req_len 不为 0
        u_cg_req.sample();// 采样 cg_req
      if (cpl_valid && cpl_ready)// 如果 cpl_valid 和 cpl_ready 都为 1
        u_cg_cpl.sample();// 采样 cg_cpl
    end
  end

endinterface