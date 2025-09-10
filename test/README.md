# Flash RAID Controller Testbench

This testbench verifies the basic functionality of the Flash RAID Controller for Tiny Tapeout submission.

## Test Coverage

### Test 1: Basic Management Interface
- Verifies management SPI register read/write functionality
- Tests default control register value (0x00)
- Tests write and read-back of control register

### Test 2: Address Range Configuration  
- Configures address range 0 (0x000000 - 0x7FFFFF)
- Verifies all 6 address range registers are written correctly
- Tests 24-bit address composition

### Test 3: Operating Mode Configuration
- Sets SHARE mode with range 0 enabled
- Verifies control register updates propagate through CDC
- Tests mode switching functionality

### Test 4: Host Interface Signal Propagation
- Verifies main host CS# propagates to flash outputs
- Tests SHARE mode behavior (both flashes active)
- Confirms signal routing in both directions

### Test 5: Host Switching (Separate Test)
- Tests switching between main and secondary host
- Verifies host selection via control register bit 6
- Confirms proper flash activation for each host

## Pin Mapping Verification

The testbench validates the Tiny Tapeout pin mapping:

```
Inputs (ui_in):
[0] main_host_sclk     [1] main_host_cs_n     [2] main_host_mosi
[3] secondary_host_sclk[4] secondary_host_cs_n [5] secondary_host_mosi  
[6] mgmt_sclk          [7] mgmt_cs_n

Outputs (uo_out):
[0] main_host_miso     [1] secondary_host_miso[2] mgmt_miso
[3] main_flash_sclk    [4] main_flash_cs_n    [5] main_flash_mosi
[6] secondary_flash_sclk[7] secondary_flash_cs_n

Bidirectional (uio_in/out):
[0] mgmt_mosi          [1] main_flash_miso    [2] secondary_flash_miso
[3] secondary_flash_mosi[4] secondary_flash_wp_n
```

## Running the Tests

### RTL Simulation
```bash
cd /tmp/flash_raid_test
make -B
```

### View Results
```bash
# Using GTKWave
gtkwave tb.vcd

# Using Surfer  
surfer tb.vcd
```

## Expected Results

- All management register operations should work correctly
- Address range configuration should be stored and retrieved accurately
- Mode switching should propagate through CDC synchronizers
- Host interfaces should properly activate flash outputs
- Both SHARE and host switching modes should function correctly

This basic testbench validates the core Flash RAID Controller functionality required for the Tiny Tapeout submission.