module dummy_dut #(parameter ADDR_W=32, DATA_W=32, LEN_W=10) (pcie_if ifc);//这里的 ifc 就是接口实例的句柄
  import pcie_pkg::*;
  // 简易内存：地址低12位做索引
  // 参数化内存地址位宽，统一索引位
  localparam int MEM_AW = 12;         // 2^12 = 4096
  logic [DATA_W-1:0] mem [0:(1<<MEM_AW)-1];

    //  [FIX] 用变量索引替代“下标里切片”
  logic [MEM_AW-1:0] widx_w;  // 写索引（(addr-base)>>2）
  logic [MEM_AW-1:0] widx_r;  // 读索引（(addr-base)>>2）

  // 顶部常量（和 pcie_pkg 对齐）
  localparam logic [63:0] MSI_ADDR  = 64'hFEE0_0000_0000_1000; //  [ADDED] demo 门铃
  // 复位寄存器
  logic [31:0] msi_cnt;                           //  [ADDED]


  // ================= [BAR-ADD] BAR0 寄存器与工具函数 =================
  // BAR0: base/size，可由 CfgWr 修改
  logic [ADDR_W-1:0] bar0_base;                 //定义了 bar0_base，用来存储 BAR0 的 base
  int unsigned       bar0_size;                 //定义了 bar0_size，用来存储 BAR0 的 size
  // 地址是否落在 BAR0
  function bit addr_in_bar0(logic [ADDR_W-1:0] a);      //定义了 addr_in_bar0 函数，用来判断地址是否落在 BAR0
    return (a >= bar0_base) && (a < bar0_base + bar0_size);// 如果 a 的值大于等于 bar0_base，且小于 bar0_base + bar0_size，则返回 true
  endfunction
  // ===================================================================

  // ================= [LTSSM-ADD] 链路门控与 CfgRd 完成仲裁寄存器 =================
  wire link_ok = ifc.link_up && !ifc.link_retrain;   // 链路就绪且不在重训练窗口时才工作
  logic        cfg_cpl_fire;                         // 本拍是否要因 CfgRd 产生完成
  logic [2:0]  cfg_cpl_status_q;
  logic [7:0]  cfg_cpl_tag_q;
  logic [DATA_W-1:0] cfg_cpl_data_q;
  // ===================================================================

  // ================= [ADDED] Completion 握手保持 + 1 深度缓冲 =================
  logic        cpl_pending;          // 当前是否有一笔待握手的完成      //  [ADDED]
  logic [2:0]  cpl_status_hold;      // 持有中的完成状态                //  [ADDED]
  logic [7:0]  cpl_tag_hold;         // 持有中的完成 tag                 //  [ADDED]
  logic [DATA_W-1:0] cpl_data_hold;  // 持有中的完成数据                //  [ADDED]
  // 额外再缓存 1 笔 MRd 完成（当上面一笔未被 ready 接受时）           //  [ADDED]
  logic        mrd_buf_vld;          //  [ADDED]
  logic [2:0]  mrd_buf_status;       //  [ADDED]
  logic [7:0]  mrd_buf_tag;          //  [ADDED]
  logic [DATA_W-1:0] mrd_buf_data;   // [ADDED]
  // ===================================================================

  // 初始化内存，避免读出 X
  integer i;
  // ---------------- 握手时序控制（关键） ----------------
  typedef enum logic [1:0] {IDLE, WAIT, ACCEPT} st_e;  // [ADDED]
  st_e st;                                             // [ADDED]
  int  wait_cnt;                                       // [ADDED]

  // pipeline for MRd
  logic        r_mrd_vld_d1, r_mrd_vld_d2;// MRd 有效标志
  logic [7:0]  r_mrd_tag_d1, r_mrd_tag_d2;// MRd 的 tag
  logic [ADDR_W-1:0] r_mrd_addr_d1, r_mrd_addr_d2;// MRd 的地址
  logic [DATA_W-1:0] r_mrd_data_d1, r_mrd_data_d2;
  logic               r_mrd_err_d1,  r_mrd_err_d2;     // [BAR-ADD] 非法地址标记随流水传递

  logic req_valid_q;                               // 上一拍的 valid
  wire  req_valid_rise = ifc.req_valid && !req_valid_q; // 上升沿脉冲

  always_ff @(posedge ifc.clk or negedge ifc.rst_n) begin
    if(!ifc.rst_n) begin// 如果复位信号为低

      // ====== 内存初始化（避免读出 X）======
      for (i = 0; i < (1<<MEM_AW); i++) begin
        mem[i] <= '0;              // 或者 <= i; 任选一个确定值
      end

      // 复位所有信号
      ifc.cpl_valid   <= 1'b0;
      ifc.cpl_status  <= 3'd0;
      ifc.cpl_tag     <= '0;
      ifc.cpl_data    <= '0;

      r_mrd_vld_d1    <= 1'b0;
      r_mrd_vld_d2    <= 1'b0;
      r_mrd_tag_d1    <= '0;// 复位 MRd 的 tag
      r_mrd_tag_d2    <= '0;// 复位 MRd 的 tag
      r_mrd_addr_d1   <= '0;
      r_mrd_addr_d2   <= '0;
      r_mrd_data_d1   <= '0;        // ★ 新增复位
      r_mrd_data_d2   <= '0;
      r_mrd_err_d1    <= 1'b0;      // [BAR-ADD]
      r_mrd_err_d2    <= 1'b0;      // [BAR-ADD]

      st       <= IDLE;        // [ADDED]
      wait_cnt <= 0;           // [ADDED]
      req_valid_q     <= 1'b0;    
      ifc.req_ready   <= 1'b0;   // [ADDED] 复位时保持 not ready

      // [BAR-ADD] BAR0 缺省：base=0x0, size=4KB
      bar0_base <= '0;
      bar0_size <= DEFAULT_BAR0_SIZE;

      // [LTSSM-ADD] CfgRd 完成仲裁寄存器复位
      cfg_cpl_fire     <= 1'b0;
      cfg_cpl_status_q <= '0;
      cfg_cpl_tag_q    <= '0;
      cfg_cpl_data_q   <= '0;

            // [ADDED] 完成持有/缓冲复位
      cpl_pending   <= 1'b0;        //  [ADDED]
      cpl_status_hold <= '0;        //  [ADDED]
      cpl_tag_hold    <= '0;        //  [ADDED]
      cpl_data_hold   <= '0;        // [ADDED]
      mrd_buf_vld     <= 1'b0;      //  [ADDED]
      mrd_buf_status  <= '0;        //  [ADDED]
      mrd_buf_tag     <= '0;        //  [ADDED]
      mrd_buf_data    <= '0;        //  [ADDED]
      msi_cnt <= '0;

    end else begin// 如果复位信号为高
      req_valid_q <= ifc.req_valid;// 保存上一拍的 valid

      // ===== [LTSSM-ADD] 链路未就绪/重训练：停机并清流水 =====
      if (!link_ok) begin
        ifc.req_ready   <= 1'b0;     // 不接收
        r_mrd_vld_d1    <= 1'b0;     // 清流水
        r_mrd_vld_d2    <= 1'b0;
        ifc.cpl_valid   <= 1'b0;     // 不吐完成
        cfg_cpl_fire    <= 1'b0;     // 清本拍 CfgRd 完成脉冲
        st              <= IDLE;     // 状态机回到 IDLE
        // 同时清除持有/缓冲，避免 link 变动期间悬空握手
        cpl_pending     <= 1'b0;     //  [ADDED]
        mrd_buf_vld     <= 1'b0;     //  [ADDED]
      end else begin
        // ---------------- 握手状态机（形成等待期） ----------------
        unique case (st)//这里的 st 就是状态机的状态变量，unique case 保证状态变量的唯一性。
          IDLE: begin//如果当前状态是 IDLE
            ifc.req_ready <= 1'b0;            // 默认不 ready
            if (req_valid_rise) begin          // 看到对端拉高 valid
              st       <= WAIT;
              wait_cnt <= 2;                  // [ADDED] 等两拍，保证存在 valid=1 && ready=0 的等待期
            end
          end

          WAIT: begin
            ifc.req_ready <= 1'b0;
            if (wait_cnt == 0) st <= ACCEPT;
            else wait_cnt <= wait_cnt - 1;
          end

          ACCEPT: begin
            ifc.req_ready <= 1'b1;            // [ADDED] 给一拍 ready=1 完成握手
            st <= IDLE;
          end
        endcase

        // ================= [BAR-MOD] 写事务：仅对 BAR0 范围内写入 =================
        if (ifc.req_valid && ifc.req_ready && ifc.req_type == TLP_MWr) begin
          if (addr_in_bar0(ifc.req_addr)) begin// 如果请求地址在 BAR0 范围内
            //  [FIX] 先计算字地址，再作为 mem 下标
            widx_w = (ifc.req_addr - bar0_base) >> 2;
            mem[widx_w] <= ifc.req_data;
          end
          else if (ifc.req_addr[ADDR_W-1:0] == MSI_ADDR[ADDR_W-1:0]) begin //  [ADDED]
            msi_cnt <= msi_cnt + 1;                                        //  [ADDED]
            $display("[%0t] MSI HIT: addr=0x%0h data=0x%08h cnt=%0d",
                    $time, ifc.req_addr, ifc.req_data, msi_cnt+1);          //  [ADDED]
          end
        end
        // ======================================================================

        // 捕获 MRd（并判断地址是否合法）
        r_mrd_vld_d1  <= (ifc.req_valid && ifc.req_ready && ifc.req_type == TLP_MRd);// 如果请求有效且准备就绪，且类型为 MRd，则设置 r_mrd_vld_d1 为 1
        if (ifc.req_valid && ifc.req_ready && ifc.req_type == TLP_MRd) begin//
          r_mrd_tag_d1   <= ifc.req_tag;// 捕获 MRd 的 tag
          r_mrd_addr_d1  <= ifc.req_addr;// 捕获 MRd 的地址
          r_mrd_err_d1   <= !addr_in_bar0(ifc.req_addr);                         // [BAR-ADD]
          if (addr_in_bar0(ifc.req_addr)) begin                                  // [BAR-ADD]
            widx_r        = (ifc.req_addr - bar0_base) >> 2;
            r_mrd_data_d1 <= mem[widx_r];
          end else begin                                                          // [BAR-ADD]
            r_mrd_data_d1 <= ERR_CODE_ILLEGAL;                                    // [BAR-ADD]
          end                                                                      // [BAR-ADD]
          $display("[%0t] MRd cap: addr=0x%08h tag=0x%0h", $time, ifc.req_addr, ifc.req_tag);
        end
        //流水推进到第 2 级
        r_mrd_vld_d2  <= r_mrd_vld_d1;// 将 r_mrd_vld_d1 的值传递到 r_mrd_vld_d2
        r_mrd_tag_d2  <= r_mrd_tag_d1;// 将 r_mrd_tag_d1 的值传递到 r_mrd_tag_d2
        r_mrd_addr_d2 <= r_mrd_addr_d1;// 将 r_mrd_addr_d1 的值传递到 r_mrd_addr_d2
        r_mrd_data_d2 <= r_mrd_data_d1;
        r_mrd_err_d2  <= r_mrd_err_d1;

        // ================= [BAR-ADD] CfgRd/CfgWr：配置 BAR0 的 base/size =================
        // 说明：CfgRd 在本拍直接产生“待发完成”，用 cfg_cpl_* 暂存，统一在末尾仲裁发出
        if (ifc.req_valid && ifc.req_ready && ifc.req_type == TLP_CfgWr) begin
          if (ifc.req_addr == CFG_BAR0_BASE_ADDR)      bar0_base <= ifc.req_data;
          else if (ifc.req_addr == CFG_BAR0_SIZE_ADDR) bar0_size <= ifc.req_data;
        end
        if (ifc.req_valid && ifc.req_ready && ifc.req_type == TLP_CfgRd) begin
          cfg_cpl_fire     <= 1'b1;                       // [LTSSM-ADD] 记下本拍要发 CfgRd 完成
          cfg_cpl_tag_q    <= ifc.req_tag;
          cfg_cpl_status_q <= 3'd0;
          if (ifc.req_addr == CFG_BAR0_BASE_ADDR)      cfg_cpl_data_q <= bar0_base[DATA_W-1:0];
          else if (ifc.req_addr == CFG_BAR0_SIZE_ADDR) cfg_cpl_data_q <= bar0_size[DATA_W-1:0];
          else begin
            cfg_cpl_data_q   <= ERR_CODE_ILLEGAL;
            cfg_cpl_status_q <= 3'd1; // 非法
          end
        end
        // ==============================================================================

               // ======================= [ADDED] 完成仲裁 + 握手保持 =======================
        // 优先级：先吐“持有的一笔”→ 若空，则先 MRd，再 CfgRd；
        // 若持有中且来新的 MRd，则放入 1 深度缓冲（mrd_buf_*），Cfg 完成通过 cfg_cpl_fire 自带保留。
        // 1) 默认下推持有的完成，直到对端 cpl_ready=1
        if (cpl_pending) begin                                      //  [ADDED]
          ifc.cpl_valid  <= 1'b1;                                   //  [ADDED]
          ifc.cpl_status <= cpl_status_hold;                        //  [ADDED]
          ifc.cpl_tag    <= cpl_tag_hold;                           // [ADDED]
          ifc.cpl_data   <= cpl_data_hold;                          //  [ADDED]
          if (ifc.cpl_ready) begin                                  //  [ADDED]
            cpl_pending <= 1'b0;                                    //  [ADDED]
            // 若缓存里有 MRd，下一拍切入持有
            if (mrd_buf_vld) begin                                  //  [ADDED]
              cpl_pending    <= 1'b1;                               //  [ADDED]
              cpl_status_hold<= mrd_buf_status;                     //  [ADDED]
              cpl_tag_hold   <= mrd_buf_tag;                        //  [ADDED]
              cpl_data_hold  <= mrd_buf_data;                       //  [ADDED]
              mrd_buf_vld    <= 1'b0;                               // [ADDED]
            end else if (cfg_cpl_fire) begin                        //  [ADDED]
              cpl_pending    <= 1'b1;                               //  [ADDED]
              cpl_status_hold<= cfg_cpl_status_q;                   //  [ADDED]
              cpl_tag_hold   <= cfg_cpl_tag_q;                      //  [ADDED]
              cpl_data_hold  <= cfg_cpl_data_q;                     //  [ADDED]
              cfg_cpl_fire   <= 1'b0;                               //  [ADDED]
            end else begin
              ifc.cpl_valid <= 1'b0;                                //  [ADDED]
            end
          end
        end else begin
          // 2) 当前无持有：先看 MRd 流水，再看 CfgRd
          if (r_mrd_vld_d2) begin                                   //  [ADDED]
            cpl_pending     <= 1'b1;                                //  [ADDED]
            cpl_status_hold <= (r_mrd_err_d2 ? 3'd1 : 3'd0);        //  [ADDED]
            cpl_tag_hold    <= r_mrd_tag_d2;                        //  [ADDED]
            cpl_data_hold   <= r_mrd_data_d2;                       //  [ADDED]
            ifc.cpl_valid   <= 1'b1;                                //  [ADDED]
            ifc.cpl_status  <= (r_mrd_err_d2 ? 3'd1 : 3'd0);        //  [ADDED]
            ifc.cpl_tag     <= r_mrd_tag_d2;                        //  [ADDED]
            ifc.cpl_data    <= r_mrd_data_d2;                       //  [ADDED]
          end else if (cfg_cpl_fire) begin                          //  [ADDED]
            cpl_pending     <= 1'b1;                                //  [ADDED]
            cpl_status_hold <= cfg_cpl_status_q;                    //  [ADDED]
            cpl_tag_hold    <= cfg_cpl_tag_q;                       // [ADDED]
            cpl_data_hold   <= cfg_cpl_data_q;                      // [ADDED]
            ifc.cpl_valid   <= 1'b1;                                // [ADDED]
            ifc.cpl_status  <= cfg_cpl_status_q;                    // [ADDED]
            ifc.cpl_tag     <= cfg_cpl_tag_q;                       // [ADDED]
            ifc.cpl_data    <= cfg_cpl_data_q;                      // [ADDED]
            cfg_cpl_fire    <= 1'b0;                                // [ADDED]
          end else begin
            ifc.cpl_valid   <= 1'b0;                                //  [ADDED]
          end
        end

        // 3) 若当前持有中且这拍又来了 MRd 完成，就塞进 1 深度缓冲
        if (cpl_pending && r_mrd_vld_d2 && !mrd_buf_vld) begin      //  [ADDED]
          mrd_buf_vld    <= 1'b1;                                   //  [ADDED]
          mrd_buf_status <= (r_mrd_err_d2 ? 3'd1 : 3'd0);           //  [ADDED]
          mrd_buf_tag    <= r_mrd_tag_d2;                           //  [ADDED]
          mrd_buf_data   <= r_mrd_data_d2;                          //  [ADDED]
        end
        // ===================== [ADDED] 完成握手保持逻辑结束 =====================

      end // link_ok
    end
  end
endmodule
