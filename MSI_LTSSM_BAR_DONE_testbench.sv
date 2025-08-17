`timescale 1ns/1ps
`include "pcie_pkg.sv"

module tb_top;
  import uvm_pkg::*;
  import pcie_pkg::*;

  // 时钟/复位
  logic clk=0, rst_n=0; always #5 clk = ~clk; // 100MHz
  initial begin #40 rst_n=1; end

  // 接口
  pcie_if #(32,32,10) vif(.clk(clk), .rst_n(rst_n));// 创建一个 pcie_if 接口实例，参数化为 32 位地址、32 位数据和 10 位长度

  // ========== [ADDED] 最小 Dummy DUT（制造等待期，再握手） ==========
  // 作用：当看到 req_valid=1 时，故意先延迟若干拍保持 ready=0，随后给一个拍 ready=1 完成握手

  // DUT
  dummy_dut #(32,32,10) dut(.ifc(vif));// 创建一个 dummy_dut 实例，参数化为 32 位地址、32 位数据和 10 位长度，并将接口 vif 传递给它

  //  LTSSM 上电/演示：复位后一段时间 link_up=1；可选演示 retrain 脉冲
  initial begin
    vif.set_link_up(1'b0);    //  上电默认未就绪
    vif.link_retrain = 1'b0;   //  无重训练事件
    @(posedge rst_n);
    repeat (5) @(posedge clk);
    vif.set_link_up(1'b1);  //  链路就绪（≈ LTSSM 进入 L0）

    //  可选：命令行加 +DEMO_RETRAIN 时，打一个 5 拍的重训练窗口
    if ($test$plusargs("DEMO_RETRAIN")) begin
      repeat (200) @(posedge clk);
      $display("[%0t] DEMO: trigger retrain (5 cycles)", $time);
      vif.do_retrain(5);
    end
  end

  initial begin
    $dumpfile("dump.vcd");    // 指定波形文件名
    $dumpvars(0, tb_top);     // 从 tb_top 记录所有信号
  end

  // 把 virtual interface 放进 config_db
  initial begin
    uvm_config_db#(virtual pcie_if)::set(null, "*", "vif", vif);// 将虚拟接口 vif 存入 UVM 配置数据库，供测试环境使用
  end

  // 运行 UVM
  initial begin
    run_test("pcie_cov_test");// 启动 UVM 测试，运行名为 "pcie_base_test" 的测试
  end
endmodule