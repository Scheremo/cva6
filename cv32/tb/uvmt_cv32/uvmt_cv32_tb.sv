//
// Copyright 2020 OpenHW Group
// Copyright 2020 Datum Technologies
// 
// Licensed under the Solderpad Hardware Licence, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
// 
//     https://solderpad.org/licenses/
// 
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
// 


`ifndef __UVMT_CV32_TB_SV__
`define __UVMT_CV32_TB_SV__


/**
 * Module encapsulating the CV32 DUT wrapper, and associated SV interfaces.
 * Also provide UVM environment entry and exit points.
 */
`default_nettype none
module uvmt_cv32_tb;

   import uvm_pkg::*;
   import uvmt_cv32_pkg::*;
   import uvme_cv32_pkg::*;

   // Capture regs for test status from Virtual Peripheral in dut_wrap.mem_i
   bit        tp;
   bit        tf;
   bit        evalid;
   bit [31:0] evalue;

   // Agent interfaces
   uvma_clknrst_if              clknrst_if(); // clock and resets from the clknrst agent
   uvma_clknrst_if              clknrst_if_iss();
   uvma_interrupt_if            interrupt_if(); // Interrupts

   // DUT Wrapper Interfaces
   uvmt_cv32_vp_status_if       vp_status_if();       // Status information generated by the Virtual Peripherals in the DUT WRAPPER memory.
   uvmt_cv32_core_cntrl_if      core_cntrl_if();      // Static and quasi-static core control inputs.
   uvmt_cv32_core_status_if     core_status_if();     // Core status outputs.   

   // Step and compare interface
   uvmt_cv32_step_compare_if step_compare_if();
   uvmt_cv32_isa_covg_if     isa_covg_if();
   
  /**
   * DUT WRAPPER instance:
   * This is an update of the riscv_wrapper.sv from PULP-Platform RI5CY project with
   * a few mods to bring unused ports from the CORE to this level using SV interfaces.
   */
   uvmt_cv32_dut_wrap  #(
                         .INSTR_ADDR_WIDTH  (32),
                         .INSTR_RDATA_WIDTH (32),
                         .RAM_ADDR_WIDTH    (22)
                        )
                        dut_wrap (.*);

  // Bind in verification modules to the design
  bind cv32e40p_core 
    uvmt_cv32e40p_interrupt_assert u_interrupt_assert(.mcause_n(cs_registers_i.mcause_n),
                                                      .mip(cs_registers_i.mip),
                                                      .mie_q(cs_registers_i.mie_q),
                                                      .mstatus_mie(cs_registers_i.mstatus_q.mie),
                                                      .mtvec_mode_q(cs_registers_i.mtvec_mode_q),
                                                      .if_stage_instr_rvalid_i(if_stage_i.instr_rvalid_i),
                                                      .if_stage_instr_rdata_i(if_stage_i.instr_rdata_i),
                                                      .id_stage_instr_valid_i(id_stage_i.instr_valid_i),
                                                      .id_stage_instr_rdata_i(id_stage_i.instr_rdata_i),
                                                      .ctrl_fsm_cs(id_stage_i.controller_i.ctrl_fsm_cs),
                                                      .exc_ctrl_cs(id_stage_i.int_controller_i.exc_ctrl_cs),
                                                      .*);
  bind cv32e40p_core 
    uvmt_cv32e40p_debug_assert u_debug_assert(.if_stage_instr_rvalid_i(if_stage_i.instr_rvalid_i),
                                               .if_stage_instr_rdata_i(if_stage_i.instr_rdata_i),
                                               .id_stage_instr_valid_i(id_stage_i.instr_valid_i),
                                               .id_stage_instr_rdata_i(id_stage_i.instr_rdata_i),
                                               .id_stage_is_compressed(id_stage_i.is_compressed_i),
                                               .id_stage_pc(id_stage_i.pc_id_i),
                                               .if_stage_pc(if_stage_i.pc_if_o),
                                               .ctrl_fsm_cs(id_stage_i.controller_i.ctrl_fsm_cs),
                                               .debug_req_i(id_stage_i.controller_i.debug_req_i),
                                               .debug_mode_q(id_stage_i.controller_i.debug_mode_q),
                                               .dcsr_q(cs_registers_i.dcsr_q),
                                               .depc_q(cs_registers_i.depc_q),
                                               .mcause_q(cs_registers_i.mcause_q),
                                               .mtvec(cs_registers_i.mtvec_addr_i),
                                               .mepc_q(cs_registers_i.mepc_q),
                                               .tdata1(cs_registers_i.tmatch_control_rdata),
                                               .tdata2(cs_registers_i.tmatch_value_rdata),
                                               .trigger_match_i(id_stage_i.controller_i.trigger_match_i),
                                               .*);

  /**
   * ISS WRAPPER instance:
   * TODO: finalize the parameters passed in.
   */
   `ifdef ISS
      uvmt_cv32_iss_wrap  #(
                            .ID (0)
                           )
                           iss_wrap ( .clk_period(clknrst_if.clk_period),
                                      .clknrst_if(clknrst_if_iss),
                                      .step_compare_if(step_compare_if),
                                      .isa_covg_if(isa_covg_if)
                             );
     /**
      * Step-and-Compare logic 
      */
      uvmt_cv32_step_compare step_compare (.clknrst_if(clknrst_if),
                                           .step_compare_if(step_compare_if) );

      //always @(dut_wrap.cv32e40p_wrapper_i.core_i.tracer_i.retire) -> step_compare_if.riscv_retire;
      //assign step_compare_if.insn_pc   = dut_wrap.cv32e40p_wrapper_i.core_i.tracer_i.insn_pc;
      //assign step_compare_if.riscy_GPR = dut_wrap.cv32e40p_wrapper_i.core_i.id_stage_i.registers_i.register_file_i.mem;
      always @(dut_wrap.cv32e40p_wrapper_i.tracer_i.retire) -> step_compare_if.riscv_retire;
      assign step_compare_if.insn_pc   = dut_wrap.cv32e40p_wrapper_i.tracer_i.insn_pc;
      assign step_compare_if.riscy_GPR = dut_wrap.cv32e40p_wrapper_i.core_i.id_stage_i.registers_i.register_file_i.mem;
      assign clknrst_if_iss.reset_n = clknrst_if.reset_n;
    
      wire [31:0] irq_enabled;
      reg [31:0] irq_deferint;
      reg [31:0] irq_mip;
      reg core_sleep_o_d;

      always @(posedge clknrst_if.clk or negedge clknrst_if.reset_n) begin
        if (!clknrst_if.reset_n)
          core_sleep_o_d <= 1'b0;
        else
          core_sleep_o_d <= dut_wrap.cv32e40p_wrapper_i.core_sleep_o;
      end

      wire id_start = dut_wrap.cv32e40p_wrapper_i.core_i.id_stage_i.id_valid_o &
                      dut_wrap.cv32e40p_wrapper_i.core_i.id_stage_i.is_decoding_o;

      assign irq_enabled = dut_wrap.cv32e40p_wrapper_i.irq_i & dut_wrap.cv32e40p_wrapper_i.core_i.cs_registers_i.mie_n;

      /**
       * step_compare_if.deferint_prime is set to 0 (asserted) when the controller in ID commits to an interrupt
         derefint_prime is then reset to 1 when the ID stage commits to the next instruction (which should be the MTVEC entry address)
      */
      always @(posedge clknrst_if.clk or negedge clknrst_if.reset_n) begin
        if (!clknrst_if_iss.reset_n)
          step_compare_if.deferint_prime <= 1'b1;
        else if (dut_wrap.cv32e40p_wrapper_i.core_i.id_stage_i.controller_i.ctrl_fsm_cs inside {cv32e40p_pkg::IRQ_TAKEN_ID,
                                                                                                cv32e40p_pkg::IRQ_TAKEN_IF})        
          step_compare_if.deferint_prime <= 1'b0;
        else if (core_sleep_o_d && irq_enabled) 
          step_compare_if.deferint_prime <= 1'b0;
        else if (id_start && !step_compare_if.deferint_prime) 
          step_compare_if.deferint_prime <= 1'b1;
      end

      /**
       * When the ID stage commits, we set deferint to the ISS to signal to look at the interrrupts
       */
      always @(posedge clknrst_if.clk or negedge clknrst_if.reset_n) begin
        if (!clknrst_if_iss.reset_n)
          iss_wrap.b1.deferint <= 1'b1;
        else if (id_start && !step_compare_if.deferint_prime) 
          iss_wrap.b1.deferint <= 1'b0;
      end

      /**
       * deferint deassertion logic, on negedge of ovp_b1_Step from the ISS the deferint has been consumed 
       */
      always @(negedge step_compare_if.ovp_b1_Step) begin
        if (iss_wrap.b1.deferint == 0) begin
          iss_wrap.b1.deferint <= 1'b1;
          irq_deferint <= '0;
        end
      end

      /**
        * irq_deferint will capture the asserted interrupt to present to the ISS later
        * since the autoclear/ack interface can clear the IRQ long before the ISS sees it
        */
      always @(posedge clknrst_if.clk or negedge clknrst_if.reset_n) begin
        if (!clknrst_if.reset_n)
          irq_deferint <= '0;
        else if (dut_wrap.cv32e40p_wrapper_i.core_i.id_stage_i.controller_i.ctrl_fsm_cs inside {cv32e40p_pkg::IRQ_TAKEN_ID,
                                                                                                cv32e40p_pkg::IRQ_TAKEN_IF})
          irq_deferint <= (1 << dut_wrap.irq_id);
        else if (core_sleep_o_d && irq_enabled)
          irq_deferint <= irq_enabled;
      end
      assign iss_wrap.b1.irq_i = !iss_wrap.b1.deferint ? irq_deferint : irq_mip;

      /**
       * Interrupt assertion to iss_wrap, note this runs on the ISS clock (skewed from core clock)
       */
      always @(posedge clknrst_if.clk or negedge clknrst_if.reset_n) begin
        if (!clknrst_if.reset_n) begin
          irq_mip <= '0;
        end
        else begin
          for (int irq_idx=0; irq_idx<32; irq_idx++) begin
                        
            // Leave ISS side asserted as long as RTL interrupt line is asserted
            if (dut_wrap.cv32e40p_wrapper_i.irq_i[irq_idx]) 
              irq_mip[irq_idx] <= 1'b1;          
            // If deferint is low and ovp_b1_Step is asserted, then interrupt was consumed by model
            // Clear it now to avoid mip miscompare
            else if (step_compare_if.ovp_b1_Step && iss_wrap.b1.deferint == 0)
              irq_mip[irq_idx] <= 1'b0;
            // If RTL interrupt deasserts, but the core has not taken the interrupt, then clear ISS irq
            else if (iss_wrap.b1.deferint == 1)
              irq_mip[irq_idx] <= 1'b0;            
          end
        end
      end

    `endif

   /**
    * Test bench entry point.
    */
   initial begin : test_bench_entry_point

     // Specify time format for simulation (units_number, precision_number, suffix_string, minimum_field_width)
     $timeformat(-9, 3, " ns", 8);
      
     // Add interfaces handles to uvm_config_db
     uvm_config_db#(virtual uvma_clknrst_if             )::set(.cntxt(null), .inst_name("*.env.clknrst_agent"), .field_name("vif"),         .value(clknrst_if));
     uvm_config_db#(virtual uvma_interrupt_if           )::set(.cntxt(null), .inst_name("*.env.interrupt_agent"), .field_name("vif"),         .value(interrupt_if));
     uvm_config_db#(virtual uvmt_cv32_vp_status_if      )::set(.cntxt(null), .inst_name("*"), .field_name("vp_status_vif"),       .value(vp_status_if)      );
     uvm_config_db#(virtual uvmt_cv32_core_cntrl_if     )::set(.cntxt(null), .inst_name("*"), .field_name("core_cntrl_vif"),      .value(core_cntrl_if)     );
     uvm_config_db#(virtual uvmt_cv32_core_status_if    )::set(.cntxt(null), .inst_name("*"), .field_name("core_status_vif"),     .value(core_status_if)    );     
     uvm_config_db#(virtual uvmt_cv32_step_compare_if   )::set(.cntxt(null), .inst_name("*"), .field_name("step_compare_vif"),    .value(step_compare_if));
     uvm_config_db#(virtual uvmt_cv32_isa_covg_if       )::set(.cntxt(null), .inst_name("*"), .field_name("isa_covg_vif"),        .value(isa_covg_if));
      
     // Make the DUT Wrapper Virtual Peripheral's status outputs available to the base_test
     uvm_config_db#(bit      )::set(.cntxt(null), .inst_name("*"), .field_name("tp"),     .value(1'b0)        );
     uvm_config_db#(bit      )::set(.cntxt(null), .inst_name("*"), .field_name("tf"),     .value(1'b0)        );
     uvm_config_db#(bit      )::set(.cntxt(null), .inst_name("*"), .field_name("evalid"), .value(1'b0)        );
     uvm_config_db#(bit[31:0])::set(.cntxt(null), .inst_name("*"), .field_name("evalue"), .value(32'h00000000));
      
     // Run test
     uvm_top.enable_print_topology = 0; // ENV coders enable this as a debug aid
     uvm_top.finish_on_completion  = 1;
     uvm_top.run_test();
   end : test_bench_entry_point

   
   // Capture the test status and exit pulse flags
   // TODO: put this logic in the vp_status_if (makes it easier to pass to ENV)
   always @(posedge clknrst_if.clk) begin
     if (!clknrst_if.reset_n) begin
       tp     <= 1'b0;
       tf     <= 1'b0;
       evalid <= 1'b0;
       evalue <= 32'h00000000;
     end
     else begin
       if (vp_status_if.tests_passed) begin
         tp <= 1'b1;
         uvm_config_db#(bit)::set(.cntxt(null), .inst_name("*"), .field_name("tp"), .value(1'b1));
       end
       if (vp_status_if.tests_failed) begin
         tf <= 1'b1;
         uvm_config_db#(bit)::set(.cntxt(null), .inst_name("*"), .field_name("tf"), .value(1'b1));
       end
       if (vp_status_if.exit_valid) begin
         evalid <= 1'b1;
         uvm_config_db#(bit)::set(.cntxt(null), .inst_name("*"), .field_name("evalid"), .value(1'b1));
       end
       if (vp_status_if.exit_valid) begin
         evalue <= vp_status_if.exit_value;
         uvm_config_db#(bit[31:0])::set(.cntxt(null), .inst_name("*"), .field_name("evalue"), .value(vp_status_if.exit_value));
       end
     end
   end

   
   /**
    * End-of-test summary printout.
    */
   final begin: end_of_test
      string             summary_string;
      uvm_report_server  rs;
      int                err_count;
      int                warning_count;
      int                fatal_count;
      static bit         sim_finished = 0;
      
      static string  red   = "\033[31m\033[1m";
      static string  green = "\033[32m\033[1m";
      static string  reset = "\033[0m";
      
      rs            = uvm_top.get_report_server();
      err_count     = rs.get_severity_count(UVM_ERROR);
      warning_count = rs.get_severity_count(UVM_WARNING);
      fatal_count   = rs.get_severity_count(UVM_FATAL);
      
      void'(uvm_config_db#(bit)::get(null, "", "sim_finished", sim_finished));

      $display("\n%m: *** Test Summary ***\n");
      
      if (sim_finished && (err_count == 0) && (fatal_count == 0)) begin
         $display("    PPPPPPP    AAAAAA    SSSSSS    SSSSSS   EEEEEEEE  DDDDDDD     ");
         $display("    PP    PP  AA    AA  SS    SS  SS    SS  EE        DD    DD    ");
         $display("    PP    PP  AA    AA  SS        SS        EE        DD    DD    ");
         $display("    PPPPPPP   AAAAAAAA   SSSSSS    SSSSSS   EEEEE     DD    DD    ");
         $display("    PP        AA    AA        SS        SS  EE        DD    DD    ");
         $display("    PP        AA    AA  SS    SS  SS    SS  EE        DD    DD    ");
         $display("    PP        AA    AA   SSSSSS    SSSSSS   EEEEEEEE  DDDDDDD     ");
         $display("    ----------------------------------------------------------");
         if (warning_count == 0) begin
           $display("                        SIMULATION PASSED                     ");
         end
         else begin
           $display("                 SIMULATION PASSED with WARNINGS              ");
         end
         $display("    ----------------------------------------------------------");
      end
      else begin
         $display("    FFFFFFFF   AAAAAA   IIIIII  LL        EEEEEEEE  DDDDDDD       ");
         $display("    FF        AA    AA    II    LL        EE        DD    DD      ");
         $display("    FF        AA    AA    II    LL        EE        DD    DD      ");
         $display("    FFFFF     AAAAAAAA    II    LL        EEEEE     DD    DD      ");
         $display("    FF        AA    AA    II    LL        EE        DD    DD      ");
         $display("    FF        AA    AA    II    LL        EE        DD    DD      ");
         $display("    FF        AA    AA  IIIIII  LLLLLLLL  EEEEEEEE  DDDDDDD       ");
         
         if (sim_finished == 0) begin
            $display("    --------------------------------------------------------");
            $display("                   SIMULATION FAILED - ABORTED              ");
            $display("    --------------------------------------------------------");
         end
         else begin
            $display("    --------------------------------------------------------");
            $display("                       SIMULATION FAILED                    ");
            $display("    --------------------------------------------------------");
         end
      end
   end
   
endmodule : uvmt_cv32_tb
`default_nettype wire

`endif // __UVMT_CV32_TB_SV__
