//MASTER 

`timescale 1ns/1ps

module spi_master
#(
	parameter	CLK_FREQUENCE	= 50_000_000		,	//system clk frequence
				SPI_FREQUENCE	= 5_000_000			,	//spi clk frequence
				DATA_WIDTH		= 8					,	//serial word length
				CPOL			= 0					,	//SPI mode selection (mode 0 default)
				CPHA			= 0					 	//CPOL = clock polarity, CPHA = clock phase
)
(
	input								clk			,	//system clk
	input								rst_n		,	//system reset
	input		[DATA_WIDTH-1:0]		data_in		,	//the data sent by mosi
	input								start		,	//a pluse to start the SPI transmission
	input								miso		,	//spi bus miso input
	output	reg							sclk		,	//spi bus sclk
	output	reg							cs_n		,	//spi bus slave select line
	output								mosi		,	//spi bus mosi output
	output	reg							finish		,	//a pluse to indicate the SPI transmission finish and the data_out valid
	output	reg [DATA_WIDTH-1:0]		data_out	 	//the data received by miso,valid when the finish is high
);

localparam	FREQUENCE_CNT	= CLK_FREQUENCE/SPI_FREQUENCE - 1	,
			SHIFT_WIDTH		= log2(DATA_WIDTH)					,
			CNT_WIDTH		= log2(FREQUENCE_CNT)				;

localparam	IDLE	=	3'b000	,
			LOAD	=	3'b001	,
			SHIFT	=	3'b010	,
			DONE	=	3'b100	;

reg		[2:0]				cstate		;	//FSM current state
reg		[2:0]				nstate		;	//FSM next state
reg							clk_cnt_en	;	//start clk_cnt to generate sclk
reg							sclk_a		;	//sclk register to capture the edge of sclk
reg							sclk_b		;	//sclk register to capture the edge of sclk
wire						sclk_posedge;	//posedge of sclk
wire						sclk_negedge;	//negedge of sclk
wire						shift_en	;	//the signal to enable shift register to generate mosi
wire						sampl_en	;	//the signal to sample the data from miso
reg		[CNT_WIDTH-1:0]		clk_cnt		;	//the counter to generate sclk
reg		[SHIFT_WIDTH-1:0]	shift_cnt	;	//the counter to count the number of shifts
reg		[DATA_WIDTH-1:0]	data_reg	;	//the register to latch the data_in,also the shift register
//the counter to generate the sclk
always @(posedge clk or negedge rst_n) begin
	if (!rst_n) 
		clk_cnt <= 'd0;
	else if (clk_cnt_en) 
		if (clk_cnt == FREQUENCE_CNT) 
			clk_cnt <= 'd0;
		else
			clk_cnt <= clk_cnt + 1'b1;
	else
		clk_cnt <= 'd0;
end
//generate the sclk
always @(posedge clk or negedge rst_n) begin
	if (!rst_n) 
		sclk <= CPOL;
	else if (clk_cnt_en) 
		if (clk_cnt == FREQUENCE_CNT)  	
			sclk <= ~sclk; 
		else 
			sclk <= sclk;
	else
		sclk <= CPOL;
end
//------------------------------------------
//to capture the edge of sclk
always @(posedge clk or negedge rst_n) begin
	if (!rst_n) begin
		sclk_a <= CPOL;
		sclk_b <= CPOL;
	end else if (clk_cnt_en) begin
		sclk_a <= sclk;
		sclk_b <= sclk_a;
	end
end

assign sclk_posedge = ~sclk_b & sclk_a;
assign sclk_negedge = ~sclk_a & sclk_b;
//----------------------------------------
//==============================================
//==============GENERATE BLOCKS=================
generate
	case (CPHA)
		0: assign sampl_en = sclk_posedge;
		1: assign sampl_en = sclk_negedge;
		default: assign sampl_en = sclk_posedge;
	endcase
endgenerate

generate
 	case (CPHA)
		0: assign shift_en = sclk_negedge;
 		1: assign shift_en = sclk_posedge;
		default: assign shift_en = sclk_posedge;
	endcase
endgenerate
//=============================================
//FSM-1
always @(posedge clk or negedge rst_n) begin
	if (!rst_n) 
		cstate <= IDLE;
	else 
		cstate <= nstate;
end
//FSM-2
always @(*) begin
	case (cstate)
		IDLE	: nstate = start ? LOAD : IDLE;
		LOAD	: nstate = SHIFT;
		SHIFT	: nstate = (shift_cnt == DATA_WIDTH) ? DONE : SHIFT;
		DONE	: nstate = IDLE;
		default: nstate = IDLE;
	endcase
end
//FSM-3
always @(posedge clk or negedge rst_n) begin
	if (!rst_n) begin
		clk_cnt_en	<= 1'b0	;
		data_reg	<= 'd0	;
		cs_n		<= 1'b1	;
		shift_cnt	<= 'd0	;
		finish <= 1'b0	;
	end else begin
		case (nstate)
			IDLE	: begin
				clk_cnt_en	<= 1'b0	;
				data_reg	<= 'd0	;
				cs_n		<= 1'b1	;
				shift_cnt	<= 'd0	;
				finish 		<= 1'b0	;
			end
			LOAD	: begin
				clk_cnt_en	<= 1'b1		;
				data_reg	<= data_in	;
				cs_n		<= 1'b0		;
				shift_cnt	<= 'd0		;
				finish 		<= 1'b0		;
			end
			SHIFT	: begin
				if (shift_en) begin
					shift_cnt	<= shift_cnt + 1'b1 ;
					data_reg	<= {data_reg[DATA_WIDTH-2:0],1'b0};
				end else begin
					shift_cnt	<= shift_cnt	;
					data_reg	<= data_reg		;
				end
				clk_cnt_en	<= 1'b1	;
				cs_n		<= 1'b0	;
				finish 		<= 1'b0	;
			end
			DONE	: begin
				clk_cnt_en	<= 1'b0	;
				data_reg	<= 'd0	;
				cs_n		<= 1'b1	;
				data_reg	<= 'd0	;
				finish 		<= 1'b1	;
			end
			default	: begin
				clk_cnt_en	<= 1'b0	;
				data_reg	<= 'd0	;
				cs_n		<= 1'b1	;
				data_reg	<= 'd0	;
				finish 		<= 1'b0	;
			end
		endcase
	end
end
//mosi output MSB first
assign mosi = data_reg[DATA_WIDTH-1];
//sample data from the miso line
always @(posedge clk or negedge rst_n) begin
	if (!rst_n) 
		data_out <= 'd0;
	else if (sampl_en) 
		data_out <= {data_out[DATA_WIDTH-1:0],miso};
	else
		data_out <= data_out;
end
//the function to get the width of data 
function integer log2(input integer v);
  begin
	log2=0;
	while(v>>log2) 
	  log2=log2+1;
  end
endfunction

endmodule

//SLAVE:

`timescale 1ns/1ps

module SPI_Slave
#(
	parameter	CLK_FREQUENCE	= 50_000_000		,	//system clk frequence
				SPI_FREQUENCE	= 5_000_000			,	//spi clk frequence
				DATA_WIDTH		= 8					,	//serial word length
				CPOL			= 1					,	//SPI mode selection (mode 0 default)
				CPHA			= 1					 	//CPOL = clock polarity, CPHA = clock phase
)
(
	input								clk			,	//system clk
	input								rst_n		,	//system reset
	input		[DATA_WIDTH-1:0]		data_in		,	//the data sent by miso
	input								sclk		,	//spi bus sclk
	input								cs_n		,	//spi bus slave select line
	input								mosi		,	//spi bus mosi input
	output								miso		,	//spi bus miso output
	output								data_valid	,	//the data received by mosi valid
	output	reg	[DATA_WIDTH-1:0]		data_out	 	//the data received by mosi,valid when data_valid is high
);

localparam	SFIFT_NUM = log2(DATA_WIDTH);

reg	[DATA_WIDTH-1:0]		data_reg	;	//the register to latch the data_in,also the shift register
reg	[ SFIFT_NUM-1:0]		sampl_num	;	//the counter to count the number of sample
reg							sclk_a		;	//sclk register to capture the edge of sclk
reg							sclk_b		;	//sclk register to capture the edge of sclk
wire						sclk_posedge;	//posedge of sclk
wire						sclk_negedge;	//negedge of sclk
reg							cs_n_a		;	//cs_n register to capture the edge of cs_n
reg							cs_n_b		;	//cs_n register to capture the edge of cs_n
wire						cs_n_negedge;	//negedge of cs_n to latch the data
wire						shift_en	;	//the signal to enable shift register to generate mosi
wire						sampl_en	;	//the signal to sample the data from miso
//------------------------------------------
//to capture the edge of sclk
always @(posedge clk or negedge rst_n) begin
	if (!rst_n) begin
		sclk_a <= CPOL;
		sclk_b <= CPOL;
	end else if (!cs_n) begin
		sclk_a <= sclk;
		sclk_b <= sclk_a;
	end
end

assign sclk_posedge = ~sclk_b & sclk_a;
assign sclk_negedge = ~sclk_a & sclk_b;
//------------------------------------------
//to capture the edge of sclk
always @(posedge clk or negedge rst_n) begin
	if (!rst_n) begin
		cs_n_a	<= 1'b1;
		cs_n_b	<= 1'b1;
	end else begin
		cs_n_a	<= cs_n		;
		cs_n_b	<= cs_n_a	;
	end
end

assign cs_n_negedge = ~cs_n_a & cs_n_b;
//------------------------------------------
//==============================================
//==============GENERATE BLOCKS=================
generate
	case (CPHA)
		0: assign sampl_en = sclk_posedge;
		1: assign sampl_en = sclk_negedge;
		default: assign sampl_en = sclk_posedge;
	endcase
endgenerate

generate
 	case (CPHA)
		0: assign shift_en = sclk_negedge;
 		1: assign shift_en = sclk_posedge;
		default: assign shift_en = sclk_posedge;
	endcase
endgenerate
//==================================================
//the register to latch the data_in
//also the shift register to generate the miso
always @(posedge clk or negedge rst_n) begin
	if (!rst_n) 
		data_reg <= 'd0;
	else if(cs_n_negedge)
		data_reg <= data_in;
	else if (!cs_n & shift_en) 
		data_reg <= {data_reg[DATA_WIDTH-2:0],1'b0};
	else
		data_reg <= data_reg;
end
//miso output MSB first
assign miso = !cs_n ? data_reg[DATA_WIDTH-1] : 1'd0;
//==================================================
//sample data from the mosi line
always @(posedge clk or negedge rst_n) begin
	if (!rst_n) 
		data_out <= 'd0;
	else if (!cs_n & sampl_en) 
		data_out <= {data_out[DATA_WIDTH-2:0],mosi};
	else
		data_out <= data_out;
end
//the counter to count the number of sampled data bit
always @(posedge clk or negedge rst_n) begin
	if (!rst_n) 
		sampl_num <= 'd0;
	else if (cs_n)
		sampl_num <= 'd0;
	else if (!cs_n & sampl_en) 
		if (sampl_num == DATA_WIDTH)
			sampl_num <= 'd1;
		else
			sampl_num <= sampl_num + 1'b1;
	else
		sampl_num <= sampl_num;
end
//the received data valid
assign data_valid = sampl_num == DATA_WIDTH;
//the function to get the width of data 
function integer log2(input integer v);
  begin
	log2=0;
	while(v>>log2) 
	  log2=log2+1;
  end
endfunction

endmodule

//TOP AKA LOOPBACK :

`timescale 1ns/1ps

module SPI_loopback
#(
	parameter	CLK_FREQUENCE	= 50_000_000		,	//system clk frequence
				SPI_FREQUENCE	= 5_000_000			,	//spi clk frequence
				DATA_WIDTH		= 8					,	//serial word length
				CPOL			= 0					,	//SPI mode selection (mode 0 default)
				CPHA			= 0					 	//CPOL = clock polarity, CPHA = clock phase
)
(
	input							clk			,
	input							rst_n		,
	input		[DATA_WIDTH-1:0]	data_m_in	,
	input		[DATA_WIDTH-1:0]	data_s_in	,
	input							start_m		,
	output							finish_m	,
	output		[DATA_WIDTH-1:0]	data_m_out	,
	output		[DATA_WIDTH-1:0]	data_s_out	,
	output							data_valid_s	 
);

wire				miso	;
wire				mosi	;
wire				cs_n	;
wire				sclk	;

spi_master 
#(
	.CLK_FREQUENCE (CLK_FREQUENCE ),
	.SPI_FREQUENCE (SPI_FREQUENCE ),
	.DATA_WIDTH    (DATA_WIDTH    ),
	.CPOL          (CPOL          ),
	.CPHA          (CPHA          ) 
)
u_spi_master(
	.clk      (clk      ),
	.rst_n    (rst_n    ),
	.data_in  (data_m_in  ),
	.start    (start_m    ),
	.miso     (miso     ),
	.sclk     (sclk     ),
	.cs_n     (cs_n     ),
	.mosi     (mosi     ),
	.finish   (finish_m   ),
	.data_out (data_m_out )
);

SPI_Slave 
#(
	.CLK_FREQUENCE (CLK_FREQUENCE ),
	.SPI_FREQUENCE (SPI_FREQUENCE ),
	.DATA_WIDTH    (DATA_WIDTH    ),
	.CPOL          (CPOL          ),
	.CPHA          (CPHA          ) 
)
u_SPI_Slave(
	.clk        (clk        ),
	.rst_n      (rst_n      ),
	.data_in    (data_s_in    ),
	.sclk       (sclk       ),
	.cs_n       (cs_n       ),
	.mosi       (mosi       ),
	.miso       (miso       ),
	.data_valid (data_valid_s ),
	.data_out   (data_s_out   )
);

endmodule