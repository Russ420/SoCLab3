`timescale 1ns / 1ps
module fir 
#(  parameter pADDR_WIDTH = 12,
    parameter pDATA_WIDTH = 32,
    parameter Tape_Num    = 11
)
(

	// axilite write
    output  reg                     awready,
    output  reg                     wready,
    input   wire                     awvalid,
    input   wire [(pADDR_WIDTH-1):0] awaddr,
    input   wire                     wvalid,
    input   wire [(pDATA_WIDTH-1):0] wdata,

	// axilite ready
    output  reg                     arready,
    input   wire                     rready,
    input   wire                     arvalid,
    input   wire [(pADDR_WIDTH-1):0] araddr,
    output  reg                     rvalid,
    output  reg [(pDATA_WIDTH-1):0] rdata,    

	// axi strmIn
    input   wire                     ss_tvalid, 
    input   wire [(pDATA_WIDTH-1):0] ss_tdata, 
		// slave tells master ready to receive data
    output  reg                    	 ss_tready, 
		// master tells slave this one is the last data
    input   wire                     ss_tlast, 

	// axi strmOut
    input   wire                     sm_tready, 
    output  reg                     sm_tvalid, 
    output  reg [(pDATA_WIDTH-1):0] sm_tdata, 
    output  reg                     sm_tlast, 
    
    // bram for tap RAM
    output  reg [3:0]               tap_WE,
    output  reg                     tap_EN,
    output  reg [(pDATA_WIDTH-1):0] tap_Di,
    output  reg [(pADDR_WIDTH-1):0] tap_A,
    input   wire [(pDATA_WIDTH-1):0] tap_Do,

    // bram for data RAM
    output  reg [3:0]               data_WE,
    output  reg                     data_EN,
    output  reg [(pDATA_WIDTH-1):0] data_Di,
    output  reg [(pADDR_WIDTH-1):0] data_A,
    input   wire [(pDATA_WIDTH-1):0] data_Do,

	// periphral clk, rst_n
    input   wire                     axis_clk,
    input   wire                     axis_rst_n

	//// debug
	//output wire [2:0]d_w_present,
	//output wire [2:0]d_w_next,

	//output wire [2:0]d_r_present,
	//output wire [2:0]d_r_next,

	//output wire [3:0] d_strmIn_present,
	//output wire [3:0] d_strmIn_next,
	//output wire d_ap_start,

	//output wire [11:0] d_data_head,
	//output wire [11:0] d_data_tail,
	//output wire [12:0] d_data_ptr,

	//output wire [11:0] d_tap_head,
	//output wire [11:0] d_tap_tail,
	//output wire [12:0] d_tap_ptr,

	//output wire [5:0]acc_state

);

begin
    // write your code here!
	// ap state
	reg [31:0]ap_state;

	reg ap_start;
	reg ap_idle;
	reg ap_done;


	
	// axiStrmIn interface
	// i don't think that the strmIn need to stall
		// strmIn state
	localparam strmIn_idle 			= 4'b0000;
	localparam strmIn_idleStall 	= 4'b0001;
	localparam strmIn_First 		= 4'b0010;
	localparam strmIn_FirstShift 	= 4'b0011;
	localparam strmIn_FirstStall 	= 4'b0100;
	localparam strmIn_Inter 		= 4'b0101;
	localparam strmIn_InterShift 	= 4'b0110;
	localparam strmIn_InterStall 	= 4'b0111;
	localparam strmIn_Zone 			= 4'b1000;
	localparam strmIn_ZoneShift 	= 4'b1001;
	localparam strmIn_ZoneStall 	= 4'b1010;
	localparam strmIn_Last 			= 4'b1011;
	localparam strmIn_LastShift 	= 4'b1100;
	localparam strmIn_done 			= 4'b1101;

		// strmIn state register
	reg [3:0]strmIn_present;
	reg [3:0]strmIn_next;

	//assign d_strmIn_present = strmIn_present;
	//assign d_strmIn_next 	= strmIn_next;

		// register for data_ram

	// 11 words
	reg [10:0] data_head;
	reg [10:0] data_tail;
	// 12bit address
	reg [11:0] data_ptr;

	// 11 words
	reg [10:0] tap_head;
	reg [10:0] tap_tail;
	// 12bit address
	reg [11:0] tap_ptr;

	reg shadow_data_empty;
	reg data_empty;

	reg shadow_tap_empty;
	reg tap_empty;

	reg shadow_first;
	reg first;

	reg shadow_last;
	reg last;

	reg [3:0]	s_tap_WE;
	reg 		s_tap_EN;
	reg [31:0]	s_tap_Di;
	reg [12:0]	s_tap_A;

	// fir_tap_addr
	reg acc_valid;
	reg acc_start;

	reg [31:0]fir_tap;
	reg [31:0]fir_data;
	reg [31:0]fir_acc;
	reg [31:0]fir_mul;
	reg [31:0]fir_out;


	//assign d_data_head 	= data_head;
	//assign d_data_tail 	= data_tail;
	//assign d_data_ptr 	= data_ptr;

	//assign d_tap_head 	= tap_head;
	//assign d_tap_tail 	= tap_tail;
	//assign d_tap_ptr 	= tap_ptr;

	always @(posedge axis_clk or negedge axis_rst_n)begin
		if(!axis_rst_n)	data_empty <= 1'b0;
		else 			data_empty <= shadow_data_empty;
	end

	always @(posedge axis_clk or negedge axis_rst_n)begin
		if(!axis_rst_n)	tap_empty <= 1'b0;
		else 			tap_empty <= shadow_tap_empty;
	end

	always @(posedge axis_clk or negedge axis_rst_n)begin
		if(!axis_rst_n)	first <= 1'b0;
		else 			first <= shadow_first;
	end

	always @(posedge axis_clk or negedge axis_rst_n)begin
		if(!axis_rst_n)	last <= 1'b0;
		else 			last <= shadow_last;
	end

	always @(posedge axis_clk or negedge axis_rst_n)begin
		if(!axis_rst_n)	fir_tap <= 32'd0;
		else 			fir_tap <= tap_Do;
	end

	always @(posedge axis_clk or negedge axis_rst_n)begin
		if(!axis_rst_n)	fir_data <= 32'd0;
		else 			fir_data <= data_Do;
	end

	always @(posedge axis_clk or negedge axis_rst_n)begin
		if(!axis_rst_n) acc_start <= 1'b0;
		else begin
			if(ap_start)
				acc_start <= ap_start;
			else 
				acc_start <= 1'b0;
		end
	end

	always @(posedge axis_clk or negedge axis_rst_n)begin
		if(!axis_rst_n) acc_valid <= 1'b0;
		else begin
			if(acc_start)begin
				if(data_empty)
					acc_valid <= 1'b0;
				else
					acc_valid <= 1'b1;
			end
			else begin
				acc_valid <= 1'b0;
			end
		end
	end

	always @(*)begin
		if(acc_valid)begin
			fir_mul = fir_data * fir_tap;
		end
		else begin
			fir_mul = 32'd0;
		end
	end

	always @(posedge axis_clk or negedge axis_rst_n)begin
		if(!axis_rst_n)
			fir_acc <= 32'd0;
		else begin
			if(acc_valid)begin
				fir_acc <= fir_acc + fir_mul;
			end
			else begin
				fir_acc <= 32'd0;
			end
		end
	end

	//assign acc_state = {ap_start, ss_tvalid, data_empty, tap_empty, first, ss_tlast};

	// axiStrmIn
	always @(posedge axis_clk or negedge axis_rst_n)begin
		if(!axis_rst_n)	strmIn_present <= strmIn_idle;
		else 			strmIn_present <= strmIn_next;
	end

	always @(*)begin
		case(strmIn_present)
			strmIn_idle:begin
				case({ap_start, ss_tvalid, data_empty, tap_empty, first, ss_tlast})
					6'b110010:strmIn_next = strmIn_idleStall;
					default:strmIn_next = strmIn_idle;
				endcase
			end
			strmIn_idleStall:begin
				case({ap_start, ss_tvalid, data_empty, tap_empty, first, ss_tlast})
					default:strmIn_next = strmIn_First;
				endcase
			end
			strmIn_First:begin
				case({ap_start, ss_tvalid, data_empty, tap_empty, first, ss_tlast})
					6'b110010:strmIn_next = strmIn_FirstShift;
					6'b111010:strmIn_next = strmIn_FirstStall;
					6'b111100:strmIn_next = strmIn_Inter;
					default:strmIn_next = strmIn_idle;
				endcase
			end
			strmIn_FirstShift:begin
				case({ap_start, ss_tvalid, data_empty, tap_empty, first, ss_tlast})
					6'b110010:strmIn_next = strmIn_First;
					6'b111010:strmIn_next = strmIn_FirstStall;
					6'b111100:strmIn_next = strmIn_Inter;
					default:strmIn_next = strmIn_idle;
				endcase
			end
			strmIn_FirstStall:begin
				case({ap_start, ss_tvalid, data_empty, tap_empty, first, ss_tlast})
					default:strmIn_next = strmIn_First;
				endcase
			end
			strmIn_Inter:begin
				case({ap_start, ss_tvalid, data_empty, tap_empty, first, ss_tlast})
					6'b110000:strmIn_next = strmIn_InterShift;
					6'b111100:strmIn_next = strmIn_InterStall;
					6'b110001:strmIn_next = strmIn_ZoneStall;
					default:strmIn_next = strmIn_idle;
				endcase
			end
			strmIn_InterShift:begin
				case({ap_start, ss_tvalid, data_empty, tap_empty, first, ss_tlast})
					6'b110000:strmIn_next = strmIn_Inter;
					6'b111100:strmIn_next = strmIn_InterStall;
					6'b110001:strmIn_next = strmIn_ZoneStall;
					default:strmIn_next = strmIn_idle;
				endcase
			end
			strmIn_InterStall:begin
				case({ap_start, ss_tvalid, data_empty, tap_empty, first, ss_tlast})
					6'b110000:strmIn_next = strmIn_Inter;
					6'b110001:strmIn_next = strmIn_Zone;
					default:strmIn_next = strmIn_idle;
				endcase
			end
			strmIn_Zone:begin
				case({ap_start, ss_tvalid, data_empty, tap_empty, first, ss_tlast})
					6'b110001:strmIn_next = strmIn_ZoneShift;
					6'b111101:strmIn_next = strmIn_ZoneStall;
					default:strmIn_next = strmIn_idle;
				endcase
			end
			strmIn_ZoneShift:begin
				case({ap_start, ss_tvalid, data_empty, tap_empty, first, ss_tlast})
					6'b110001:strmIn_next = strmIn_Zone;
					6'b111101:strmIn_next = strmIn_ZoneStall;
					default:strmIn_next = strmIn_idle;
				endcase
			end
			strmIn_ZoneStall:begin
				case({ap_start, ss_tvalid, data_empty, tap_empty, first, ss_tlast})
				 	6'b110001:strmIn_next = strmIn_Last;
					default:strmIn_next = strmIn_idle;
				endcase
			end
			strmIn_Last:begin
				case({ap_start, ss_tvalid, data_empty, tap_empty, first, ss_tlast})
					6'b110001:strmIn_next = strmIn_LastShift;
					6'b111101:strmIn_next = strmIn_done;
					default:strmIn_next = strmIn_idle;
				endcase
			end
			strmIn_LastShift:begin
				case({ap_start, ss_tvalid, data_empty, tap_empty, first, ss_tlast})
					6'b110001:strmIn_next = strmIn_Last;
					6'b111101:strmIn_next = strmIn_done;
					default:strmIn_next = strmIn_idle;
				endcase
			end
			strmIn_done:begin
				case({ap_start, ss_tvalid, data_empty, tap_empty, first, ss_tlast})
					default:strmIn_next = strmIn_done;
				endcase
			end
			default: strmIn_next = strmIn_idle;
		endcase
	end

	always @(*)begin
		case(data_ptr)
			12'h001: data_A = 12'h000;
			12'h002: data_A = 12'h001;
			12'h004: data_A = 12'h002;
			12'h008: data_A = 12'h003;
			12'h010: data_A = 12'h004;
			12'h020: data_A = 12'h005;
			12'h040: data_A = 12'h006;
			12'h080: data_A = 12'h007;
			12'h100: data_A = 12'h008;
			12'h200: data_A = 12'h009;
			12'h400: data_A = 12'h00A;
			default: data_A = 12'h00A;
		endcase
	end
	
	always @(*)begin
		case(tap_ptr)
			12'h001: s_tap_A = 12'h020;
			12'h002: s_tap_A = 12'h024;
			12'h004: s_tap_A = 12'h028;
			12'h008: s_tap_A = 12'h02C;
			12'h010: s_tap_A = 12'h030;
			12'h020: s_tap_A = 12'h034;
			12'h040: s_tap_A = 12'h038;
			12'h080: s_tap_A = 12'h03C;
			12'h100: s_tap_A = 12'h040;
			12'h200: s_tap_A = 12'h044;
			12'h400: s_tap_A = 12'h048;
			default: s_tap_A = 12'h400;
		endcase
	end

	always @(*)begin
		case(strmIn_present)
			strmIn_idle:begin
				case({ap_start, ss_tvalid, data_empty, tap_empty, first, ss_tlast})
					6'b110010:begin
						ss_tready 	= 1'b1;

						data_head 	= 11'h001;
						data_tail 	= 11'h001;
						data_ptr	= {1'b0, data_head};
						
						tap_head 	= 11'h001;
						tap_tail 	= 11'h400;
						tap_ptr		= {1'b0, tap_head};

						data_WE = {4{ss_tready}};
						data_EN = 1'b1;
						data_Di = ss_tdata;

						s_tap_WE = 4'h0;
						s_tap_EN = 1'b1;
						s_tap_Di = ss_tdata;

					end
					default:begin
						ss_tready 	= 1'b0;

						data_head 	= 11'h001;
						data_tail 	= 11'h001;
						data_ptr	= {1'b0, data_head};
						
						tap_head 	= 11'h001;
						tap_tail 	= 11'h400;
						tap_ptr		= {1'b0, tap_head};

						shadow_first 	 	= 1'b1;
						shadow_data_empty 	= 1'b0;
						shadow_tap_empty 	= 1'b0;

						data_WE = {4{ss_tready}};
						data_EN = 1'b1;
						data_Di = ss_tdata;

						s_tap_WE = 4'h0;
						s_tap_EN = 1'b1;
						s_tap_Di = ss_tdata;

					end
				endcase
			end
			strmIn_idleStall:begin
				case({ap_start, ss_tvalid, data_empty, tap_empty, first, ss_tlast})
					default:begin
						ss_tready 	= 1'b0;

						data_head 	= data_head;
						data_tail 	= data_tail;
						data_ptr	= data_ptr;
						
						tap_head 	= tap_head;
						tap_tail 	= tap_tail;
						tap_ptr		= tap_ptr;

						if(data_ptr == data_tail)
							shadow_data_empty 	= 1'b1;
						else
							shadow_data_empty = 1'b0;

						if(tap_ptr == tap_tail)
							shadow_tap_empty 	= 1'b1;
						else
							shadow_tap_empty = 1'b0;

						if(tap_ptr == tap_tail)
							shadow_first 	= 1'b0;
						else
							shadow_first = shadow_first;

						data_WE = {4{ss_tready}};
						data_EN = 1'b1;
						data_Di = ss_tdata;

						s_tap_WE = 4'h0;
						s_tap_EN = 1'b1;
						s_tap_Di = ss_tdata;
					end
				endcase
			end
			strmIn_First:begin
				case({ap_start, ss_tvalid, data_empty, tap_empty, first, ss_tlast})
					6'b110010:begin // read out 

						ss_tready 	= 1'b0;

						data_head 	= data_head;
						data_tail 	= 11'h001;
						data_ptr	= data_ptr >> 1;
						
						tap_head 	= 11'h001;
						tap_tail 	= 11'h400;
						tap_ptr		= tap_ptr << 1;

						if(data_ptr == {1'b0, data_tail})
							shadow_data_empty 	= 1'b1;
						else
							shadow_data_empty = 1'b0;

						if(tap_ptr == tap_tail)
							shadow_tap_empty 	= 1'b1;
						else
							shadow_tap_empty = 1'b0;

						if(tap_ptr == tap_tail)
							shadow_first 	= 1'b0;
						else
							shadow_first = shadow_first;

						data_WE = {4{ss_tready}};
						data_EN = 1'b1;
						data_Di = ss_tdata;

						s_tap_WE = 4'h0;
						s_tap_EN = 1'b1;
						s_tap_Di = ss_tdata;
					end
					6'b111010:begin // update data ram

						ss_tready 	= 1'b1;

						data_head 	= data_head << 1;
						data_tail 	= 11'h001;
						data_ptr	= {1'b0, data_head};
						
						tap_head 	= 11'h001;
						tap_tail 	= 11'h400;
						tap_ptr		= {1'b0, tap_head};

						if(data_ptr == data_tail)
							shadow_data_empty 	= 1'b1;
						else
							shadow_data_empty = 1'b0;

						if(tap_ptr == tap_tail)
							shadow_tap_empty 	= 1'b1;
						else
							shadow_tap_empty = 1'b0;

						if(tap_ptr == tap_tail)
							shadow_first 	= 1'b0;
						else
							shadow_first = shadow_first;

						data_WE = {4{ss_tready}};
						data_EN = 1'b1;
						data_Di = ss_tdata;
						data_A 	= data_ptr;

						s_tap_WE = 4'h0;
						s_tap_EN = 1'b1;
						s_tap_Di = ss_tdata;
					end
					6'b111100:begin // change to inter

						ss_tready 	= 1'b1;

						if(data_head << 1 == 11'h000)
							data_head = 11'h001;
						else
							data_head = data_head << 1;
						data_tail 	= data_tail << 1;
						data_ptr	= {1'b0, data_head};
						
						tap_head 	= 11'h001;
						tap_tail 	= 11'h400;
						tap_ptr		= {1'b0, tap_head};

						if(data_ptr == data_tail)
							shadow_data_empty 	= 1'b1;
						else
							shadow_data_empty = 1'b0;

						if(tap_ptr == tap_tail)
							shadow_tap_empty 	= 1'b1;
						else
							shadow_tap_empty = 1'b0;

						if(tap_ptr == tap_tail)
							shadow_first 	= 1'b0;
						else
							shadow_first = shadow_first;

						data_WE = {4{ss_tready}};
						data_EN = 1'b1;
						data_Di = ss_tdata;

						s_tap_WE = 4'h0;
						s_tap_EN = 1'b1;
						s_tap_Di = ss_tdata;

					end
					default:begin
						ss_tready 	= 1'b0;

						data_head 	= 11'h001;
						data_tail 	= 11'h001;
						data_ptr	= {1'b0, data_head};
						
						tap_head 	= 11'h001;
						tap_tail 	= 11'h400;
						tap_ptr		= {1'b0, tap_head};

						shadow_first 	 	= 1'b1;
						shadow_data_empty 	= 1'b0;
						shadow_tap_empty 	= 1'b0;

						data_WE = {4{ss_tready}};
						data_EN = 1'b1;
						data_Di = ss_tdata;

						s_tap_WE = 4'h0;
						s_tap_EN = 1'b1;
						s_tap_Di = ss_tdata;

					end
				endcase
			end
			strmIn_FirstShift:begin
				case({ap_start, ss_tvalid, data_empty, tap_empty, first, ss_tlast})
					6'b110010:begin // read out

						ss_tready 	= 1'b0;

						data_head 	= data_head;
						data_tail 	= 11'h001;
						data_ptr	= data_ptr >> 1;
						
						tap_head 	= 11'h001;
						tap_tail 	= 11'h400;
						tap_ptr		= tap_ptr << 1;

						if(data_ptr == data_tail)
							shadow_data_empty 	= 1'b1;
						else
							shadow_data_empty = 1'b0;

						if(tap_ptr == tap_tail)
							shadow_tap_empty 	= 1'b1;
						else
							shadow_tap_empty = 1'b0;

						if(tap_ptr == tap_tail)
							shadow_first 	= 1'b0;
						else
							shadow_first = shadow_first;

						data_WE = {4{ss_tready}};
						data_EN = 1'b1;
						data_Di = ss_tdata;

						s_tap_WE = 4'h0;
						s_tap_EN = 1'b1;
						s_tap_Di = ss_tdata;

					end
					6'b111010:begin  // write in
						ss_tready 	= 1'b1;

						data_head 	= data_head << 1;
						data_tail 	= 11'h001;
						data_ptr	= {1'b0, data_head};
						
						tap_head 	= 11'h001;
						tap_tail 	= 11'h400;
						tap_ptr		= {1'b0, tap_head};

						if(data_ptr == data_tail)
							shadow_data_empty 	= 1'b1;
						else
							shadow_data_empty = 1'b0;

						if(tap_ptr == tap_tail)
							shadow_tap_empty 	= 1'b1;
						else
							shadow_tap_empty = 1'b0;

						if(tap_ptr == tap_tail)
							shadow_first 	= 1'b0;
						else
							shadow_first = shadow_first;

						data_WE = {4{ss_tready}};
						data_EN = 1'b1;
						data_Di = ss_tdata;

						s_tap_WE = 4'h0;
						s_tap_EN = 1'b1;
						s_tap_Di = ss_tdata;

					end
					6'b111100:begin // change to inter

						ss_tready 	= 1'b1;

						if(data_head << 1 == 11'h000)
							data_head = 11'h001;
						else
							data_head = data_head >> 1;

						if(data_tail << 1 == 11'h000)
							data_tail = 11'h001;
						else
							data_tail 	= data_tail << 1;

						data_ptr	= {1'b0, data_head};
						
						tap_head 	= 11'h001;
						tap_tail 	= 11'h400;
						tap_ptr		= {1'b0, tap_head};

						if(data_ptr == data_tail)
							shadow_data_empty 	= 1'b1;
						else
							shadow_data_empty = 1'b0;

						if(tap_ptr == tap_tail)
							shadow_tap_empty 	= 1'b1;
						else
							shadow_tap_empty = 1'b0;

						if(tap_ptr == tap_tail)
							shadow_first 	= 1'b0;
						else
							shadow_first = shadow_first;

						data_WE = {4{ss_tready}};
						data_EN = 1'b1;
						data_Di = ss_tdata;

						s_tap_WE = 4'h0;
						s_tap_EN = 1'b1;
						s_tap_Di = ss_tdata;
					end
					default:begin
						ss_tready 	= 1'b0;

						data_head 	= 11'h001;
						data_tail 	= 11'h001;
						data_ptr	= {1'b0, data_head};
						
						tap_head 	= 11'h001;
						tap_tail 	= 11'h400;
						tap_ptr		= {1'b0, tap_head};

						shadow_first 	 	= 1'b1;
						shadow_data_empty 	= 1'b0;
						shadow_tap_empty 	= 1'b0;

						data_WE = {4{ss_tready}};
						data_EN = 1'b1;
						data_Di = ss_tdata;

						s_tap_WE = 4'h0;
						s_tap_EN = 1'b1;
						s_tap_Di = ss_tdata;
					end
				endcase
			end
			strmIn_FirstStall:begin
				case({ap_start, ss_tvalid, data_empty, tap_empty, first, ss_tlast})
				  	default:begin
						ss_tready 	= 1'b0;

						data_head 	= data_head;
						data_tail 	= data_tail;
						data_ptr	= data_ptr;
						
						tap_head 	= tap_head;
						tap_tail 	= tap_tail;
						tap_ptr		= tap_ptr;

						if(data_ptr == data_tail)
							shadow_data_empty 	= 1'b1;
						else
							shadow_data_empty = 1'b0;

						if(tap_ptr == tap_tail)
							shadow_tap_empty 	= 1'b1;
						else
							shadow_tap_empty = 1'b0;

						if(tap_ptr == tap_tail)
							shadow_first 	= 1'b0;
						else
							shadow_first = shadow_first;

						data_WE = {4{ss_tready}};
						data_EN = 1'b1;
						data_Di = ss_tdata;

						s_tap_WE = 4'h0;
						s_tap_EN = 1'b1;
						s_tap_Di = ss_tdata;

					end
				endcase
			end
			strmIn_Inter:begin
				case({ap_start, ss_tvalid, data_empty, tap_empty, first, ss_tlast})
					6'b110000:begin
						ss_tready 	= 1'b0;

						data_head 	= data_head;
						data_tail 	= data_tail;
						if(data_ptr >> 1 == 12'h000)
							data_ptr = 12'h400;
						else
							data_ptr = data_ptr >> 1;
						
						tap_head 	= 11'h001;
						tap_tail 	= 11'h400;
						tap_ptr		= tap_ptr << 1;

						if(data_ptr == data_tail)
							shadow_data_empty 	= 1'b1;
						else
							shadow_data_empty = 1'b0;

						if(tap_ptr == tap_tail)
							shadow_tap_empty 	= 1'b1;
						else
							shadow_tap_empty = 1'b0;

						if(tap_ptr == tap_tail)
							shadow_first 	= 1'b0;
						else
							shadow_first = shadow_first;

						data_WE = {4{ss_tready}};
						data_EN = 1'b1;
						data_Di = ss_tdata;

						s_tap_WE = 4'h0;
						s_tap_EN = 1'b1;
						s_tap_Di = ss_tdata;
					end
					6'b111100:begin
						ss_tready 	= 1'b1;

						if(data_head << 1 == 11'h000)
							data_head = 11'h001;
						else 
							data_head = data_head << 1;
						
						if(data_tail << 1 == 11'h000)
							data_tail = 11'h001;
						else
							data_tail = data_tail << 1;

						data_ptr = {1'b0, data_head};
						
						tap_head 	= 11'h001;
						tap_tail 	= 11'h400;
						tap_ptr		= {1'b0, tap_head};

						if(data_ptr == data_tail)
							shadow_data_empty 	= 1'b1;
						else
							shadow_data_empty = 1'b0;

						if(tap_ptr == tap_tail)
							shadow_tap_empty 	= 1'b1;
						else
							shadow_tap_empty = 1'b0;

						if(tap_ptr == tap_tail)
							shadow_first 	= 1'b0;
						else
							shadow_first = shadow_first;

						data_WE = {4{ss_tready}};
						data_EN = 1'b1;
						data_Di = ss_tdata;

						s_tap_WE = 4'h0;
						s_tap_EN = 1'b1;
						s_tap_Di = ss_tdata;
					end
					6'b111101:begin
						
						ss_tready 	= 1'b1;

						if(data_head << 1 == 11'h000)
							data_head = 11'h001;
						else
							data_head = data_head << 1;
						data_tail 	= data_tail << 1;
						data_ptr	= {1'b0, data_head};
						
						tap_head 	= 11'h001;
						tap_tail 	= 11'h400;
						tap_ptr		= {1'b0, tap_head};

						if(data_ptr == data_tail)
							shadow_data_empty 	= 1'b1;
						else
							shadow_data_empty = 1'b0;

						if(tap_ptr == tap_tail)
							shadow_tap_empty 	= 1'b1;
						else
							shadow_tap_empty = 1'b0;

						if(tap_ptr == tap_tail)
							shadow_first 	= 1'b0;
						else
							shadow_first = shadow_first;

						data_WE = {4{ss_tready}};
						data_EN = 1'b1;
						data_Di = ss_tdata;

						s_tap_WE = 4'h0;
						s_tap_EN = 1'b1;
						s_tap_Di = ss_tdata;
					end
					default:begin
						ss_tready 	= 1'b0;

						data_head 	= 11'h001;
						data_tail 	= 11'h001;
						data_ptr	= {1'b0, data_head};
						
						tap_head 	= 11'h001;
						tap_tail 	= 11'h400;
						tap_ptr		= {1'b0, tap_head};

						shadow_first 	 	= 1'b1;
						shadow_data_empty 	= 1'b0;
						shadow_tap_empty 	= 1'b0;

						data_WE = {4{ss_tready}};
						data_EN = 1'b1;
						data_Di = ss_tdata;

						s_tap_WE = 4'h0;
						s_tap_EN = 1'b1;
						s_tap_Di = ss_tdata;

					end
				endcase
			end
			strmIn_InterShift:begin
				case({ap_start, ss_tvalid, data_empty, tap_empty, first, ss_tlast})
					6'b110000:begin
						ss_tready 	= 1'b0;

						data_head 	= data_head;
						data_tail 	= data_tail;
						if(data_ptr >> 1 == 12'h000)
							data_ptr = 12'h400;
						else
							data_ptr = data_ptr >> 1;
						
						tap_head 	= 11'h001;
						tap_tail 	= 11'h400;
						tap_ptr		= tap_ptr << 1;

						if(data_ptr == data_tail)
							shadow_data_empty 	= 1'b1;
						else
							shadow_data_empty = 1'b0;

						if(tap_ptr == tap_tail)
							shadow_tap_empty 	= 1'b1;
						else
							shadow_tap_empty = 1'b0;

						if(tap_ptr == tap_tail)
							shadow_first 	= 1'b0;
						else
							shadow_first = shadow_first;

						data_WE = {4{ss_tready}};
						data_EN = 1'b1;
						data_Di = ss_tdata;

						s_tap_WE = 4'h0;
						s_tap_EN = 1'b1;
						s_tap_Di = ss_tdata;
					end
					6'b111100:begin
						ss_tready 	= 1'b1;

						if(data_head << 1 == 11'h000)
							data_head = 11'h001;
						else 
							data_head = data_head << 1;
						
						if(data_tail << 1 == 11'h000)
							data_tail = 11'h001;
						else
							data_tail = data_tail << 1;

						data_ptr = {1'b0, data_head};
						
						tap_head 	= 11'h001;
						tap_tail 	= 11'h400;
						tap_ptr		= {1'b0, tap_head};

						if(data_ptr == data_tail)
							shadow_data_empty 	= 1'b1;
						else
							shadow_data_empty = 1'b0;

						if(tap_ptr == tap_tail)
							shadow_tap_empty 	= 1'b1;
						else
							shadow_tap_empty = 1'b0;

						if(tap_ptr == tap_tail)
							shadow_first 	= 1'b0;
						else
							shadow_first = shadow_first;

						data_WE = {4{ss_tready}};
						data_EN = 1'b1;
						data_Di = ss_tdata;

						s_tap_WE = 4'h0;
						s_tap_EN = 1'b1;
						s_tap_Di = ss_tdata;
					end
					6'b111101:begin

						ss_tready 	= 1'b1;

						if(data_head << 1 == 11'h000)
							data_head = 11'h001;
						else
							data_head = data_head << 1;
						data_tail 	= data_tail << 1;
						data_ptr	= {1'b0, data_head};
						
						tap_head 	= 11'h001;
						tap_tail 	= 11'h400;
						tap_ptr		= {1'b0, tap_head};

						if(data_ptr == data_tail)
							shadow_data_empty 	= 1'b1;
						else
							shadow_data_empty = 1'b0;

						if(tap_ptr == tap_tail)
							shadow_tap_empty 	= 1'b1;
						else
							shadow_tap_empty = 1'b0;

						if(tap_ptr == tap_tail)
							shadow_first 	= 1'b0;
						else
							shadow_first = shadow_first;

						data_WE = {4{ss_tready}};
						data_EN = 1'b1;
						data_Di = ss_tdata;

						s_tap_WE = 4'h0;
						s_tap_EN = 1'b1;
						s_tap_Di = ss_tdata;

					end
					default:begin
						ss_tready 	= 1'b0;

						data_head 	= 11'h001;
						data_tail 	= 11'h001;
						data_ptr	= {1'b0, data_head};
						
						tap_head 	= 11'h001;
						tap_tail 	= 11'h400;
						tap_ptr		= {1'b0, tap_head};

						shadow_first 	 	= 1'b1;
						shadow_data_empty 	= 1'b0;
						shadow_tap_empty 	= 1'b0;

						data_WE = {4{ss_tready}};
						data_EN = 1'b1;
						data_Di = ss_tdata;

						s_tap_WE = 4'h0;
						s_tap_EN = 1'b1;
						s_tap_Di = ss_tdata;

					end
				endcase
			end
			strmIn_InterStall:begin
				case({ap_start, ss_tvalid, data_empty, tap_empty, first, ss_tlast})
				  	6'b110000:begin
						ss_tready 	= 1'b0;

						data_head 	= data_head;
						data_tail 	= data_tail;
						data_ptr	= data_ptr;
						
						tap_head 	= tap_head;
						tap_tail 	= tap_tail;
						tap_ptr		= tap_ptr;

						if(data_ptr == data_tail)
							shadow_data_empty 	= 1'b1;
						else
							shadow_data_empty = 1'b0;

						if(tap_ptr == tap_tail)
							shadow_tap_empty 	= 1'b1;
						else
							shadow_tap_empty = 1'b0;

						if(tap_ptr == tap_tail)
							shadow_first 	= 1'b0;
						else
							shadow_first = shadow_first;

						data_WE = {4{ss_tready}};
						data_EN = 1'b1;
						data_Di = ss_tdata;

						s_tap_WE = 4'h0;
						s_tap_EN = 1'b1;
						s_tap_Di = ss_tdata;
					end
				 	6'b110001:begin
						ss_tready 	= 1'b0;

						if(data_head >> 1 == 11'h000)
							data_head = 11'h400;
						else
							data_head = data_head >> 1;
							
						if(data_tail >> 1 == 11'h000)
							data_tail = 11'h400;
						else
							data_tail 	= data_tail >> 1;
						data_ptr	= {1'b0, data_head};
					
						tap_head 	= tap_head;
						tap_tail 	= tap_tail;
						tap_ptr		= tap_ptr;

						if(data_ptr == data_tail)
							shadow_data_empty 	= 1'b1;
						else
							shadow_data_empty = 1'b0;

						if(tap_ptr == tap_tail)
							shadow_tap_empty 	= 1'b1;
						else
							shadow_tap_empty = 1'b0;

						if(tap_ptr == tap_tail)
							shadow_first 	= 1'b0;
						else
							shadow_first = shadow_first;

						data_WE = {4{ss_tready}};
						data_EN = 1'b1;
						data_Di = ss_tdata;

						s_tap_WE = 4'h0;
						s_tap_EN = 1'b1;
						s_tap_Di = ss_tdata;
					end
					default:begin
						ss_tready 	= 1'b0;

						data_head 	= 11'h001;
						data_tail 	= 11'h001;
						data_ptr	= {1'b0, data_head};
						
						tap_head 	= 11'h001;
						tap_tail 	= 11'h400;
						tap_ptr		= {1'b0, tap_head};

						shadow_first 	 	= 1'b1;
						shadow_data_empty 	= 1'b0;
						shadow_tap_empty 	= 1'b0;

						data_WE = {4{ss_tready}};
						data_EN = 1'b1;
						data_Di = ss_tdata;

						s_tap_WE = 4'h0;
						s_tap_EN = 1'b1;
						s_tap_Di = ss_tdata;
					end
				endcase
			end
			strmIn_Zone:begin
				case({ap_start, ss_tvalid, data_empty, tap_empty, first, ss_tlast})
					6'b110001:begin
						ss_tready 	= 1'b0;

						data_head 	= data_head;
						data_tail 	= data_tail;
						if(data_ptr >> 1 == 12'h000)
							data_ptr = 12'h400;
						else
							data_ptr = data_ptr >> 1;
						
						tap_head 	= 11'h001;
						tap_tail 	= 11'h400;
						tap_ptr		= tap_ptr << 1;

						if(data_ptr == data_tail)
							shadow_data_empty 	= 1'b1;
						else
							shadow_data_empty = 1'b0;

						if(tap_ptr == tap_tail)
							shadow_tap_empty 	= 1'b1;
						else
							shadow_tap_empty = 1'b0;

						if(tap_ptr == tap_tail)
							shadow_first 	= 1'b0;
						else
							shadow_first = shadow_first;

						data_WE = {4{ss_tready}};
						data_EN = 1'b1;
						data_Di = ss_tdata;

						s_tap_WE = 4'h0;
						s_tap_EN = 1'b1;
						s_tap_Di = ss_tdata;
					end
					6'b111101:begin
						ss_tready 	= 1'b1;

						if(data_head << 1 == 11'h000)
							data_head = 11'h001;
						else 
							data_head = data_head << 1;
						
						if(data_tail << 1 == 11'h000)
							data_tail = 11'h001;
						else
							data_tail = data_tail << 1;

						data_ptr = {1'b0, data_head};
						
						tap_head 	= 11'h001;
						tap_tail 	= 11'h400;
						tap_ptr		= {1'b0, tap_head};

						if(data_ptr == data_tail)
							shadow_data_empty 	= 1'b1;
						else
							shadow_data_empty = 1'b0;

						if(tap_ptr == tap_tail)
							shadow_tap_empty 	= 1'b1;
						else
							shadow_tap_empty = 1'b0;

						if(tap_ptr == tap_tail)
							shadow_first 	= 1'b0;
						else
							shadow_first = shadow_first;

						data_WE = {4{ss_tready}};
						data_EN = 1'b1;
						data_Di = ss_tdata;

						s_tap_WE = 4'h0;
						s_tap_EN = 1'b1;
						s_tap_Di = ss_tdata;
					end
					default:begin
						ss_tready 	= 1'b0;

						data_head 	= 11'h001;
						data_tail 	= 11'h001;
						data_ptr	= {1'b0, data_head};
						
						tap_head 	= 11'h001;
						tap_tail 	= 11'h400;
						tap_ptr		= {1'b0, tap_head};

						shadow_first 	 	= 1'b1;
						shadow_data_empty 	= 1'b0;
						shadow_tap_empty 	= 1'b0;

						data_WE = {4{ss_tready}};
						data_EN = 1'b1;
						data_Di = ss_tdata;

						s_tap_WE = 4'h0;
						s_tap_EN = 1'b1;
						s_tap_Di = ss_tdata;
					end
				endcase
			end
			strmIn_ZoneShift:begin
				case({ap_start, ss_tvalid, data_empty, tap_empty, first, ss_tlast})
					6'b110001:begin
						ss_tready 	= 1'b0;

						data_head 	= data_head;
						data_tail 	= data_tail;
						if(data_ptr >> 1 == 12'h000)
							data_ptr = 12'h400;
						else
							data_ptr = data_ptr >> 1;
						
						tap_head 	= 11'h001;
						tap_tail 	= 11'h400;
						tap_ptr		= tap_ptr << 1;

						if(data_ptr == data_tail)
							shadow_data_empty 	= 1'b1;
						else
							shadow_data_empty = 1'b0;

						if(tap_ptr == tap_tail)
							shadow_tap_empty 	= 1'b1;
						else
							shadow_tap_empty = 1'b0;

						if(tap_ptr == tap_tail)
							shadow_first 	= 1'b0;
						else
							shadow_first = shadow_first;

						data_WE = {4{ss_tready}};
						data_EN = 1'b1;
						data_Di = ss_tdata;

						s_tap_WE = 4'h0;
						s_tap_EN = 1'b1;
						s_tap_Di = ss_tdata;

					end
					6'b111101:begin
						ss_tready 	= 1'b1;

						if(data_head << 1 == 11'h000)
							data_head = 11'h001;
						else 
							data_head = data_head << 1;
						
						if(data_tail << 1 == 11'h000)
							data_tail = 11'h001;
						else
							data_tail = data_tail << 1;

						data_ptr = {1'b0, data_head};
						
						tap_head 	= 11'h001;
						tap_tail 	= 11'h400;
						tap_ptr		= {1'b0, tap_head};

						if(data_ptr == data_tail)
							shadow_data_empty 	= 1'b1;
						else
							shadow_data_empty = 1'b0;

						if(tap_ptr == tap_tail)
							shadow_tap_empty 	= 1'b1;
						else
							shadow_tap_empty = 1'b0;

						if(tap_ptr == tap_tail)
							shadow_first 	= 1'b0;
						else
							shadow_first = shadow_first;

						data_WE = {4{ss_tready}};
						data_EN = 1'b1;
						data_Di = ss_tdata;

						s_tap_WE = 4'h0;
						s_tap_EN = 1'b1;
						s_tap_Di = ss_tdata;

					end
					default:begin
						ss_tready 	= 1'b0;

						data_head 	= 11'h001;
						data_tail 	= 11'h001;
						data_ptr	= {1'b0, data_head};
						
						tap_head 	= 11'h001;
						tap_tail 	= 11'h400;
						tap_ptr		= {1'b0, tap_head};

						shadow_first 	 	= 1'b1;
						shadow_data_empty 	= 1'b0;
						shadow_tap_empty 	= 1'b0;

						data_WE = {4{ss_tready}};
						data_EN = 1'b1;
						data_Di = ss_tdata;

						s_tap_WE = 4'h0;
						s_tap_EN = 1'b1;
						s_tap_Di = ss_tdata;

					end
				endcase
			end
			strmIn_ZoneStall:begin
				case({ap_start, ss_tvalid, data_empty, tap_empty, first, ss_tlast})
				 	6'b110001:begin
						ss_tready 	= 1'b0;

						data_head 	= data_head;
						data_tail 	= data_tail;
						data_ptr	= data_ptr;
						
						tap_head 	= tap_head;
						tap_tail 	= tap_tail;
						tap_ptr		= tap_ptr;

						if(data_ptr == data_tail)
							shadow_data_empty 	= 1'b1;
						else
							shadow_data_empty = 1'b0;

						if(tap_ptr == tap_tail)
							shadow_tap_empty 	= 1'b1;
						else
							shadow_tap_empty = 1'b0;

						if(tap_ptr == tap_tail)
							shadow_first 	= 1'b0;
						else
							shadow_first = shadow_first;

						data_WE = {4{ss_tready}};
						data_EN = 1'b1;
						data_Di = ss_tdata;

						s_tap_WE = 4'h0;
						s_tap_EN = 1'b1;
						s_tap_Di = ss_tdata;
					end
					default:begin
						ss_tready 	= 1'b0;

						data_head 	= data_head;
						data_tail 	= data_tail;
						data_ptr	= data_ptr;
						
						tap_head 	= tap_head;
						tap_tail 	= tap_tail;
						tap_ptr		= tap_ptr;

						if(data_ptr == data_tail)
							shadow_data_empty 	= 1'b1;
						else
							shadow_data_empty = 1'b0;

						if(tap_ptr == tap_tail)
							shadow_tap_empty 	= 1'b1;
						else
							shadow_tap_empty = 1'b0;

						if(tap_ptr == tap_tail)
							shadow_first 	= 1'b0;
						else
							shadow_first = shadow_first;

						data_WE = {4{ss_tready}};
						data_EN = 1'b1;
						data_Di = ss_tdata;

						s_tap_WE = 4'h0;
						s_tap_EN = 1'b1;
						s_tap_Di = ss_tdata;
					end
				endcase
			end
			strmIn_Last:begin
				case({ap_start, ss_tvalid, data_empty, tap_empty, first, ss_tlast})
					6'b110001:begin
						ss_tready 	= 1'b0;

						data_head 	= data_head;
						data_tail 	= data_tail;
						if(data_ptr >> 1 == 12'h000)
							data_ptr = 12'h400;
						else
							data_ptr = data_ptr >> 1;
						
						tap_head 	= 11'h001;
						tap_tail 	= 11'h400;
						tap_ptr		= tap_ptr << 1;

						if(data_ptr == data_tail)
							shadow_data_empty 	= 1'b1;
						else
							shadow_data_empty = 1'b0;

						if(tap_ptr == tap_tail)
							shadow_tap_empty 	= 1'b1;
						else
							shadow_tap_empty = 1'b0;

						if(tap_ptr == tap_tail)
							shadow_first 	= 1'b0;
						else
							shadow_first = shadow_first;

						data_WE = {4{ss_tready}};
						data_EN = 1'b1;
						data_Di = ss_tdata;

						s_tap_WE = 4'h0;
						s_tap_EN = 1'b1;
						s_tap_Di = ss_tdata;
					end
					6'b111101:begin
						ss_tready 	= 1'b0;

						data_head 	= data_head;
						data_tail 	= data_tail;
						data_ptr	= data_ptr;
						
						tap_head 	= tap_head;
						tap_tail 	= tap_tail;
						tap_ptr		= tap_ptr;

						if(data_ptr == data_tail)
							shadow_data_empty 	= 1'b1;
						else
							shadow_data_empty = 1'b0;

						if(tap_ptr == tap_tail)
							shadow_tap_empty 	= 1'b1;
						else
							shadow_tap_empty = 1'b0;

						if(tap_ptr == tap_tail)
							shadow_first 	= 1'b0;
						else
							shadow_first = shadow_first;

						data_WE = {4{ss_tready}};
						data_EN = 1'b1;
						data_Di = ss_tdata;

						s_tap_WE = 4'h0;
						s_tap_EN = 1'b1;
						s_tap_Di = ss_tdata;

					end
					default:begin
						ss_tready 	= 1'b0;

						data_head 	= 11'h001;
						data_tail 	= 11'h001;
						data_ptr	= {1'b0, data_head};
						
						tap_head 	= 11'h001;
						tap_tail 	= 11'h400;
						tap_ptr		= {1'b0, tap_head};

						shadow_first 	 	= 1'b1;
						shadow_data_empty 	= 1'b0;
						shadow_tap_empty 	= 1'b0;

						data_WE = {4{ss_tready}};
						data_EN = 1'b1;
						data_Di = ss_tdata;

						s_tap_WE = 4'h0;
						s_tap_EN = 1'b1;
						s_tap_Di = ss_tdata;

					end
				endcase
			end
			strmIn_LastShift:begin
				case({ap_start, ss_tvalid, data_empty, tap_empty, first, ss_tlast})
					6'b110001:begin
						ss_tready 	= 1'b0;

						data_head 	= data_head;
						data_tail 	= data_tail;
						if(data_ptr >> 1 == 12'h000)
							data_ptr = 12'h400;
						else
							data_ptr = data_ptr >> 1;
						
						tap_head 	= 11'h001;
						tap_tail 	= 11'h400;
						tap_ptr		= tap_ptr << 1;

						if(data_ptr == data_tail)
							shadow_data_empty 	= 1'b1;
						else
							shadow_data_empty = 1'b0;

						if(tap_ptr == tap_tail)
							shadow_tap_empty 	= 1'b1;
						else
							shadow_tap_empty = 1'b0;

						if(tap_ptr == tap_tail)
							shadow_first 	= 1'b0;
						else
							shadow_first = shadow_first;

						data_WE = {4{ss_tready}};
						data_EN = 1'b1;
						data_Di = ss_tdata;

						s_tap_WE = 4'h0;
						s_tap_EN = 1'b1;
						s_tap_Di = ss_tdata;
					end
					6'b111101:begin
						ss_tready 	= 1'b0;

						data_head 	= data_head;
						data_tail 	= data_tail;
						data_ptr	= data_ptr;
						
						tap_head 	= tap_head;
						tap_tail 	= tap_tail;
						tap_ptr		= tap_ptr;

						if(data_ptr == data_tail)
							shadow_data_empty 	= 1'b1;
						else
							shadow_data_empty = 1'b0;

						if(tap_ptr == tap_tail)
							shadow_tap_empty 	= 1'b1;
						else
							shadow_tap_empty = 1'b0;

						if(tap_ptr == tap_tail)
							shadow_first 	= 1'b0;
						else
							shadow_first = shadow_first;

						data_WE = {4{ss_tready}};
						data_EN = 1'b1;
						data_Di = ss_tdata;

						s_tap_WE = 4'h0;
						s_tap_EN = 1'b1;
						s_tap_Di = ss_tdata;

					end
					default:begin
						ss_tready 	= 1'b0;

						data_head 	= 11'h001;
						data_tail 	= 11'h001;
						data_ptr	= {1'b0, data_head};
						
						tap_head 	= 11'h001;
						tap_tail 	= 11'h400;
						tap_ptr		= {1'b0, tap_head};

						shadow_first 	 	= 1'b1;
						shadow_data_empty 	= 1'b0;
						shadow_tap_empty 	= 1'b0;

						data_WE = {4{ss_tready}};
						data_EN = 1'b1;
						data_Di = ss_tdata;

						s_tap_WE = 4'h0;
						s_tap_EN = 1'b1;
						s_tap_Di = ss_tdata;

					end
				endcase
			end
			strmIn_done:begin
				case({ap_start, ss_tvalid, data_empty, tap_empty, first, ss_tlast})
					default:begin
						ss_tready 	= 1'b0;

						data_head 	= 11'h001;
						data_tail 	= 11'h001;
						data_ptr	= {1'b0, data_head};
						
						tap_head 	= 11'h001;
						tap_tail 	= 11'h400;
						tap_ptr		= {1'b0, tap_head};

						shadow_first 	 	= 1'b1;
						shadow_data_empty 	= 1'b0;
						shadow_tap_empty 	= 1'b0;

						data_WE = {4{ss_tready}};
						data_EN = 1'b1;
						data_Di = ss_tdata;

						s_tap_WE = 4'h0;
						s_tap_EN = 1'b1;
						s_tap_Di = ss_tdata;

					end
				endcase
			end
			default: strmIn_next = strmIn_idle;
		endcase
	end

	localparam strmOut_idle 		= 4'b0000;
	localparam strmOut_Fire 		= 4'b0001; 
	localparam strmOut_FireShift 	= 4'b0010; 
	localparam strmOut_done			= 4'b0100;

	reg [3:0] strmOut_present;
	reg [3:0] strmOut_next;

	reg out_start;

	always @(posedge axis_clk or negedge axis_rst_n)begin
		if(!axis_rst_n) out_start <= 1'b0;
		else out_start <= acc_start;
	end
	
	always @(posedge axis_clk or negedge axis_rst_n)begin
		if(!axis_rst_n)	strmOut_present <= strmOut_idle;	
		else 			strmOut_present <= strmOut_next;
	end

	always @(*)begin
		case(strmOut_present)
			strmOut_idle:begin
				if(out_start && !acc_valid && sm_tready)begin
					if(strmIn_present == 4'b1101)begin
						sm_tvalid = 1'b1;
						sm_tlast = 1'b1;
						sm_tdata = fir_acc;
					end
					else begin 							
						sm_tvalid = 1'b1;
						sm_tlast = 1'b0;
						sm_tdata = fir_acc;
					end
				end
				else begin
					sm_tvalid = 1'b0;
					sm_tlast = 1'b0;
					sm_tdata = 32'd0;
				end
			end
			strmOut_Fire:begin
				if(out_start && !acc_valid &&sm_tready)begin
					if(strmIn_present == 4'b1101)begin
						sm_tvalid = 1'b1;
						sm_tlast = 1'b1;
						sm_tdata = fir_acc;
					end
					else begin							
						sm_tvalid = 1'b1;
						sm_tlast = 1'b0;
						sm_tdata = fir_acc;
					end
				end
				else begin
					sm_tvalid = 1'b0;
					sm_tlast = 1'b0;
					sm_tdata = 32'd0;
				end
			end
			strmOut_FireShift:begin
				if(out_start && !acc_valid && sm_tready)begin
					if(strmIn_present == 4'b1101)begin
						sm_tvalid = 1'b1;
						sm_tlast = 1'b1;
						sm_tdata = fir_acc;
					end
					else begin							
						sm_tvalid = 1'b1;
						sm_tlast = 1'b0;
						sm_tdata = fir_acc;
					end
				end
				else begin
					sm_tvalid = 1'b0;
					sm_tlast = 1'b0;
					sm_tdata = 32'd0;
				end
			end

			strmOut_done:begin
				sm_tvalid = 1'b0;
				sm_tlast = 1'b0;
				sm_tdata = 32'd0;
			end

			default:begin
				sm_tvalid = 1'b0;
				sm_tlast = 1'b0;
				sm_tdata = 32'd0;
			end
			
		endcase
	end

	always @(*)begin
		case(strmOut_present)
			strmOut_idle:begin
				if(out_start && !acc_valid && sm_tready)begin
					if(strmIn_present == 4'b1101)begin
						strmOut_next = strmOut_done;
					end
					else begin 							
						strmOut_next = strmOut_Fire;
					end
				end
				else begin
					strmOut_next = strmOut_idle;
				end
			end
			strmOut_Fire:begin
				if(out_start && !acc_valid &&sm_tready)begin
					if(strmIn_present == 4'b1101)begin
						strmOut_next = strmOut_done;
					end
					else begin							
						strmOut_next = strmOut_FireShift;
					end
				end
				else begin
					strmOut_next = strmOut_idle;
				end
			end
			strmOut_FireShift:begin
				if(out_start && !acc_valid && sm_tready)begin
					if(strmIn_present == 4'b1101)begin
						strmOut_next = strmOut_done;
					end
					else begin							
						strmOut_next = strmOut_Fire;
					end
				end
				else begin
					strmOut_next = strmOut_idle;
				end
			end
			strmOut_done:begin
				strmOut_next = strmOut_idle;
			end
			default:begin
				strmOut_next = strmOut_idle;
			end
			
		endcase
	end
	


	
	// axilite read interface
		// axilite read state 
	localparam r_idle = 3'b000;

		// axilite read state register
	reg [2:0] r_present;
	reg [2:0] r_next;
	
	reg [3:0]	r_tap_WE;
	reg 		r_tap_EN;
	reg [31:0]	r_tap_Di;
	reg [11:0]	r_tap_A;


	// axilite read interface

		// axilite state register
	always@(posedge axis_clk or negedge axis_rst_n)begin
		if(!axis_rst_n)	r_present <= r_idle;
		else 			r_present <= r_next;
	end

	always@(*)begin
		case(r_present)
			default: 	r_present = r_idle;
		endcase
		
	end

		// next state logic
	always@(*)begin
		case(r_present)
			r_idle:begin
				case({arvalid, rready})
					2'b11:begin
						arready = 1'b1; 
						rvalid	= 1'b1; 
						r_tap_WE = 4'h0; 
						r_tap_EN = 1'b1; 
						r_tap_Di = data_Di; 
						r_tap_A = araddr;
					end

					default:begin
						arready = 1'b0; 
						rvalid	= 1'b0; 
						r_tap_WE = 4'h0; 
						r_tap_EN = 1'b1; 
						r_tap_Di = data_Di; 
						r_tap_A = araddr;
					end

				endcase
			end
		endcase
	end

	
	// axilite write interface
	// use 3-state to transaction
		// axilite write state

	localparam w_idle 	= 3'b000;
	// ap_start
	localparam w_s		= 3'b001;
	// non-ap_start
	localparam w_ns 	= 3'b010;
	// non-ap_start
	localparam w_done 	= 3'b100;

		// axilite write state register
	reg [2:0]w_present;
	reg [2:0]w_next;

	assign d_ap_start = ap_start;
	assign d_w_present = w_present;
	assign d_w_next = w_next;

	reg [3:0]	w_tap_WE;
	reg 		w_tap_EN;
	reg [31:0]	w_tap_Di;
	reg [11:0]	w_tap_A;

	// Noted: need to use mealy machine to write it
	// axilite write interface
		// state register
	always@(posedge axis_clk or negedge axis_rst_n)begin
		if(!axis_rst_n)	w_present <= w_idle;
		else 			w_present <= w_next;
	end

		// next state logic determined by input
		// input would be awvalid, wvalid, and tap_Di
	always@(*)begin
		case(w_present)
			w_idle:begin
				case({awvalid, wvalid})
					2'b11:begin
						if(awaddr==12'h000)
							w_next = w_s;
						else
							w_next = w_ns;
					end
					default: w_next = w_idle;
				endcase
			end
			w_s:
				w_next = w_done;

			w_done:
				w_next = w_done;

			w_ns:
				w_next = w_idle;
			default:
				w_next = w_idle;
		endcase
	end

	always@(*)begin
		case(w_present)

			w_idle: begin

				case({awvalid, wvalid})
					2'b11:begin
						if(awaddr==12'h000)begin
							//ap_start = ap_start;
							// axilite signal
							awready = 1'b1; 
							wready = 1'b1;
							// bram signal
							w_tap_WE = 4'hf; 
							w_tap_EN = 1'b1; 
							w_tap_Di = wdata; 
							w_tap_A = awaddr;
						end
						else begin
							//ap_start = ap_start;
							// axilite signal
							awready = 1'b1; 
							wready = 1'b1; 
							// bram signal
							w_tap_WE = 4'hf; 
							w_tap_EN = 1'b1; 
							w_tap_Di = wdata; 
							w_tap_A = awaddr;
						end
					end

					default:begin
						//ap_start = ap_start;
						// axilite signal
						awready = 1'b0; 
						wready = 1'b0; 
						// bram signal
						w_tap_WE = 4'h0; 
						w_tap_EN = 1'b0; 
						w_tap_Di = 32'h0000_0000; 
						w_tap_A = 12'h000;
					end
				endcase
			end
			
			w_s:begin
				//ap_start = 1'b1;
				// axilite signal
				awready = 1'b0; 
				wready = 1'b0; 
				// bram signal
				w_tap_WE = 4'h0; 
				w_tap_EN = 1'b0; 
				w_tap_Di = w_tap_Di; 
				w_tap_A = w_tap_A;
			end

			w_done:begin
				//ap_start = ap_start;
				// axilite signal
				awready = 1'b0; 
				wready = 1'b0; 
				// bram signal
				w_tap_WE = 4'h0;
				w_tap_EN = 1'b0; 
				w_tap_Di = w_tap_Di; 
				w_tap_A = w_tap_A;
			end

			w_ns:begin
				//ap_start = 1'b0;
				// axilite signal
				awready = 1'b0; 
				wready = 1'b0; 
				// bram signal
				w_tap_WE = w_tap_WE; 
				w_tap_EN = w_tap_EN; 
				w_tap_Di = w_tap_Di; 
				w_tap_A = w_tap_A;
			end

			default: begin 
				//ap_start = ap_start;
				// axilite signal
				awready = 1'b0; 
				wready = 1'b0; 
				// bram signal
				w_tap_WE = 4'h0; 
				w_tap_EN = 1'b0; 
				w_tap_Di = w_tap_Di; 
				w_tap_A = w_tap_A;
			end

		endcase
	end 

	reg [2:0]tap_state;
	wire w_tap;
	wire r_tap;
	wire s_tap;

	assign w_tap = awvalid & wvalid;
	assign r_tap = arvalid & rready;
	assign s_tap = ap_start;

	always @(*)begin
		casez({s_tap, r_tap, w_tap})
			3'b1??:begin
				tap_WE 	= s_tap_WE;
				tap_EN 	= s_tap_EN;
				tap_Di 	= s_tap_Di;
				tap_A 	= s_tap_A;
			end

			3'b??1:begin
				tap_WE 	= w_tap_WE;
				tap_EN 	= w_tap_EN;
				tap_Di 	= w_tap_Di;
				tap_A 	= w_tap_A;
			end

			3'b?1?:begin
				tap_WE 	= r_tap_WE;
				tap_EN 	= r_tap_EN;
				tap_Di 	= r_tap_Di;
				tap_A 	= r_tap_A;
			end

			default:begin
				tap_WE 	= tap_WE;
				tap_EN 	= tap_EN;
				tap_Di 	= tap_Di;
				tap_A 	= tap_A;
			end
		endcase
	end

	reg idle_ap_start;
	always @(posedge axis_clk or negedge axis_rst_n)begin
		if(!axis_rst_n)begin
			ap_start <= 1'b0;
		end
		else begin
			if(awaddr == 12'h000 && wdata==32'h0000_0001 && !ss_tlast)begin
				ap_start <= 1'b1;
			end
			else begin
				if(strmIn_present == 4'b1101)
					ap_start <= 1'b0;
				else
					ap_start <= ap_start;
			end
		end
	end

	always @(posedge axis_clk or negedge axis_rst_n)begin
		if(!axis_rst_n)	idle_ap_start <= 1'b0;
		else begin
			if(ss_tlast)
				idle_ap_start <= 1'b0;
			else
				idle_ap_start <= ap_start; 
		end
	end
	always @(*)begin
		ap_done = ~ap_start;
	end
	always @(*)begin
		ap_idle = ~ap_start;
	end
	reg [31:0]ap_r_data;

	always @(*)begin
		ap_r_data = {{29{1'b0}}, {ap_idle}, {ap_done}, {idle_ap_start}};
	end

	always @(*)begin
		if(ss_tlast)
			rdata = ap_r_data;
		else begin
			if(ap_start)
				rdata = ap_r_data;
			else
				rdata = tap_Do;
		end
	end

end


endmodule
