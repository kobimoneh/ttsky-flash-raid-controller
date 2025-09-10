# SPDX-FileCopyrightText: © 2024 Tiny Tapeout
# SPDX-License-Identifier: Apache-2.0

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, Timer


class FlashRAIDTester:
    """Helper class for Flash RAID Controller testing"""
    
    def __init__(self, dut):
        self.dut = dut
        
    async def reset(self):
        """Reset the Flash RAID Controller"""
        self.dut.ena.value = 1
        self.dut.ui_in.value = 0
        self.dut.uio_in.value = 0
        self.dut.rst_n.value = 0
        await ClockCycles(self.dut.clk, 10)
        self.dut.rst_n.value = 1
        await ClockCycles(self.dut.clk, 10)
        
    async def setup_spi_idle(self):
        """Set all SPI interfaces to idle state"""
        # All CS# signals high (inactive)
        ui_idle = (1 << 7) | (1 << 4) | (1 << 1)  # mgmt_cs_n, sh_cs_n, mh_cs_n
        self.dut.ui_in.value = ui_idle
        
        # Set flash MISO patterns for testing
        # uio_in[1] = main flash MISO, uio_in[2] = secondary flash MISO
        uio_idle = (1 << 1) | (0 << 2)  # Main=0xFF, Secondary=0x00
        self.dut.uio_in.value = uio_idle
        
        await ClockCycles(self.dut.clk, 5)
    
    async def send_mgmt_command(self, cmd, addr, data=None):
        """Send management SPI command"""
        # Management SPI: ui[6]=sclk, ui[7]=cs_n, uio[0]=mosi, uo[2]=miso
        
        # Start transaction: CS# low
        ui_val = self.dut.ui_in.value & ~(1 << 7)  # Clear mgmt_cs_n
        self.dut.ui_in.value = ui_val
        await Timer(1, units="us")
        
        # Send command byte
        await self._send_byte_mgmt(cmd)
        
        # Send address byte  
        await self._send_byte_mgmt(addr)
        
        # Send/receive data byte
        if data is not None:
            await self._send_byte_mgmt(data)
            result = None
        else:
            result = await self._recv_byte_mgmt()
            
        # End transaction: CS# high
        ui_val = self.dut.ui_in.value | (1 << 7)  # Set mgmt_cs_n
        self.dut.ui_in.value = ui_val
        await Timer(1, units="us")
        
        return result
    
    async def _send_byte_mgmt(self, byte_val):
        """Send byte via management SPI (bit-bang)"""
        for bit_idx in range(8):
            bit = (byte_val >> (7 - bit_idx)) & 1
            
            # Set MOSI
            uio_val = self.dut.uio_in.value
            if bit:
                uio_val |= (1 << 0)  # Set uio[0] (mgmt_mosi)
            else:
                uio_val &= ~(1 << 0)  # Clear uio[0]
            self.dut.uio_in.value = uio_val
            await Timer(500, units="ns")
            
            # Rising edge (sample)
            ui_val = self.dut.ui_in.value | (1 << 6)  # Set mgmt_sclk
            self.dut.ui_in.value = ui_val
            await Timer(500, units="ns")
            
            # Falling edge
            ui_val = self.dut.ui_in.value & ~(1 << 6)  # Clear mgmt_sclk
            self.dut.ui_in.value = ui_val
            await Timer(500, units="ns")
    
    async def _recv_byte_mgmt(self):
        """Receive byte via management SPI"""
        result = 0
        for bit_idx in range(8):
            # Set MOSI low during reads
            uio_val = self.dut.uio_in.value & ~(1 << 0)
            self.dut.uio_in.value = uio_val
            await Timer(500, units="ns")
            
            # Rising edge (sample MISO)
            ui_val = self.dut.ui_in.value | (1 << 6)  # Set mgmt_sclk
            self.dut.ui_in.value = ui_val
            await Timer(500, units="ns")
            
            # Read MISO (uo[2])
            miso_bit = (int(self.dut.uo_out.value) >> 2) & 1
            result = (result << 1) | miso_bit
            
            # Falling edge
            ui_val = self.dut.ui_in.value & ~(1 << 6)  # Clear mgmt_sclk
            self.dut.ui_in.value = ui_val
            await Timer(500, units="ns")
            
        return result


@cocotb.test()
async def test_flash_raid_basic(dut):
    """Basic Flash RAID Controller functionality test"""
    
    dut._log.info("Starting Flash RAID Controller Test")

    # Set the clock period to 20 ns (50 MHz)
    clock = Clock(dut.clk, 20, units="ns")
    cocotb.start_soon(clock.start())

    # Create tester instance
    tester = FlashRAIDTester(dut)
    
    # Reset and initialize
    dut._log.info("Resetting DUT...")
    await tester.reset()
    await tester.setup_spi_idle()
    
    # Test 1: Read default control register (should be 0x00)
    dut._log.info("Test 1: Reading default control register...")
    control_val = await tester.send_mgmt_command(0x03, 0x0C)  # READ, CONTROL_REG
    dut._log.info(f"Control register value: 0x{control_val:02X}")
    assert control_val == 0x00, f"Expected 0x00, got 0x{control_val:02X}"
    
    # Test 2: Write and read back control register
    dut._log.info("Test 2: Writing control register...")
    await tester.send_mgmt_command(0x02, 0x0C, 0x42)  # WRITE, CONTROL_REG, test pattern
    await ClockCycles(dut.clk, 10)  # Wait for CDC
    
    control_val = await tester.send_mgmt_command(0x03, 0x0C)  # READ back
    dut._log.info(f"Read back control register: 0x{control_val:02X}")
    assert control_val == 0x42, f"Expected 0x42, got 0x{control_val:02X}"
    
    # Test 3: Configure address range
    dut._log.info("Test 3: Configuring address range 0...")
    # Set range 0: 0x000000 - 0x7FFFFF
    await tester.send_mgmt_command(0x02, 0x00, 0x00)  # ADDR0_START_H
    await tester.send_mgmt_command(0x02, 0x01, 0x00)  # ADDR0_START_M  
    await tester.send_mgmt_command(0x02, 0x02, 0x00)  # ADDR0_START_L
    await tester.send_mgmt_command(0x02, 0x03, 0x7F)  # ADDR0_END_H
    await tester.send_mgmt_command(0x02, 0x04, 0xFF)  # ADDR0_END_M
    await tester.send_mgmt_command(0x02, 0x05, 0xFF)  # ADDR0_END_L
    
    # Verify the range was written correctly
    start_h = await tester.send_mgmt_command(0x03, 0x00)
    start_m = await tester.send_mgmt_command(0x03, 0x01) 
    start_l = await tester.send_mgmt_command(0x03, 0x02)
    end_h = await tester.send_mgmt_command(0x03, 0x03)
    end_m = await tester.send_mgmt_command(0x03, 0x04)
    end_l = await tester.send_mgmt_command(0x03, 0x05)
    
    start_addr = (start_h << 16) | (start_m << 8) | start_l
    end_addr = (end_h << 16) | (end_m << 8) | end_l
    
    dut._log.info(f"Range 0: 0x{start_addr:06X} - 0x{end_addr:06X}")
    assert start_addr == 0x000000, f"Start address mismatch: got 0x{start_addr:06X}"
    assert end_addr == 0x7FFFFF, f"End address mismatch: got 0x{end_addr:06X}"
    
    # Test 4: Set SHARE mode with range enabled
    dut._log.info("Test 4: Enabling SHARE mode with range 0...")
    # Control register: SHARE mode (0x02) + Range 0 enable (0x04) = 0x06
    await tester.send_mgmt_command(0x02, 0x0C, 0x06)
    await ClockCycles(dut.clk, 20)  # Wait for CDC synchronization
    
    control_val = await tester.send_mgmt_command(0x03, 0x0C)
    dut._log.info(f"Final control register: 0x{control_val:02X}")
    assert control_val == 0x06, f"Expected 0x06, got 0x{control_val:02X}"
    
    # Test 5: Basic host interface check (just verify signals propagate)
    dut._log.info("Test 5: Basic host interface signal check...")
    
    # Set main host CS# low, verify it reaches flash outputs
    ui_val = dut.ui_in.value & ~(1 << 1)  # Clear mh_cs_n
    dut.ui_in.value = ui_val
    await ClockCycles(dut.clk, 5)
    
    # Check that flash CS# signals respond (in SHARE mode, both should be active)
    mf_cs_n = (int(dut.uo_out.value) >> 4) & 1  # uo[4] 
    sf_cs_n = (int(dut.uo_out.value) >> 7) & 1  # uo[7]
    dut._log.info(f"Flash CS# signals: mf_cs_n={mf_cs_n}, sf_cs_n={sf_cs_n}")
    
    # In SHARE mode, both flashes should be selected when host is active
    assert mf_cs_n == 0, "Main flash CS# should be active in SHARE mode"
    assert sf_cs_n == 0, "Secondary flash CS# should be active in SHARE mode"
    
    # Return to idle
    ui_val = dut.ui_in.value | (1 << 1)  # Set mh_cs_n high
    dut.ui_in.value = ui_val
    await ClockCycles(dut.clk, 5)
    
    dut._log.info("✅ All tests passed! Flash RAID Controller is working correctly.")


@cocotb.test()
async def test_host_switching(dut):
    """Test dual host switching functionality"""
    
    dut._log.info("Starting Host Switching Test")

    # Set the clock period to 20 ns (50 MHz)
    clock = Clock(dut.clk, 20, units="ns")
    cocotb.start_soon(clock.start())

    tester = FlashRAIDTester(dut)
    
    # Reset and initialize
    await tester.reset()
    await tester.setup_spi_idle()
    
    # Configure for host switching test
    dut._log.info("Configuring SHARE mode...")
    await tester.send_mgmt_command(0x02, 0x0C, 0x02)  # SHARE mode only
    await ClockCycles(dut.clk, 10)
    
    # Test main host (default)
    dut._log.info("Testing main host interface...")
    ui_val = dut.ui_in.value & ~(1 << 1)  # Clear mh_cs_n (main host active)
    dut.ui_in.value = ui_val
    await ClockCycles(dut.clk, 5)
    
    # Check flash outputs respond
    flash_active = ((int(dut.uo_out.value) >> 4) & 1) == 0  # mf_cs_n should be low
    assert flash_active, "Main host should activate flash outputs"
    
    # Return to idle
    ui_val = dut.ui_in.value | (1 << 1)
    dut.ui_in.value = ui_val
    await ClockCycles(dut.clk, 5)
    
    # Switch to secondary host
    dut._log.info("Switching to secondary host...")
    await tester.send_mgmt_command(0x02, 0x0C, 0x42)  # SHARE mode + secondary host
    await ClockCycles(dut.clk, 20)  # Wait for CDC
    
    # Test secondary host
    dut._log.info("Testing secondary host interface...")
    ui_val = dut.ui_in.value & ~(1 << 4)  # Clear sh_cs_n (secondary host active)
    dut.ui_in.value = ui_val
    await ClockCycles(dut.clk, 5)
    
    # Check flash outputs respond
    flash_active = ((int(dut.uo_out.value) >> 4) & 1) == 0  # Flash should be active
    assert flash_active, "Secondary host should activate flash outputs"
    
    # Return to idle
    ui_val = dut.ui_in.value | (1 << 4)
    dut.ui_in.value = ui_val
    await ClockCycles(dut.clk, 5)
    
    dut._log.info("✅ Host switching test passed!")