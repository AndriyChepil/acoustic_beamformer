
#include "xil_io.h"
#include "xil_printf.h"
#include "sleep.h"
#include "xil_types.h"

#define BEAM_BASE    0x40000000U
#define GPIO_BASE    0x41200000U

#define REG_CTRL     0x00U
#define REG_DELAY0   0x04U
#define REG_DELAY1   0x08U
#define REG_DELAY2   0x0CU
#define REG_DELAY3   0x10U
#define REG_DELAY4   0x14U
#define REG_STATUS   0x18U
#define REG_PEAK     0x1CU
#define REG_COUNT    0x20U

#define GPIO_DATA    0x00U
#define GPIO_TRI     0x04U

#define PEAK_STEP    0x10000U

#define UPDATE_US    50000U
#define RESET_TICKS  10U

// Broadside direction, five microphones in one row
static const u32 delays[5] = {
    0U, 0U, 0U, 0U, 0U
};


static u32 peak_to_leds(u32 peak)
{
    u32 level = peak / PEAK_STEP;

    if (level > 8U)
        level = 8U;

    if (level == 0U)
        return 0U;

    return (1U << level) - 1U;
}

static void beamformer_set_delays(void)
{
    Xil_Out32(BEAM_BASE + REG_DELAY0, delays[0]);
    Xil_Out32(BEAM_BASE + REG_DELAY1, delays[1]);
    Xil_Out32(BEAM_BASE + REG_DELAY2, delays[2]);
    Xil_Out32(BEAM_BASE + REG_DELAY3, delays[3]);
    Xil_Out32(BEAM_BASE + REG_DELAY4, delays[4]);

    // Apply configuration: bit 1 = delay_update
    Xil_Out32(BEAM_BASE + REG_CTRL, 0x02U);

    // Enable beamformer, bit 0 = 1
    Xil_Out32(BEAM_BASE + REG_CTRL, 0x01U);
}


int main(void)
{
    u32 ctrl, status, peak, count;
    u32 leds;
    u32 ticks = 0;

    xil_printf("\r\nBeamformer VU meter started\r\n");

    // Configure LED GPIO as outputs
    Xil_Out32(GPIO_BASE + GPIO_TRI, 0x00000000U);
    Xil_Out32(GPIO_BASE + GPIO_DATA, 0x00000000U);

    // Enable beamformer
    Xil_Out32(BEAM_BASE + REG_CTRL, 0x01U);

     // Configure and enable beamformer
    beamformer_set_delays();

    xil_printf("Beamformer configured\r\n");

    while (1)
    {
        ctrl   = Xil_In32(BEAM_BASE + REG_CTRL);
        status = Xil_In32(BEAM_BASE + REG_STATUS);
        peak   = Xil_In32(BEAM_BASE + REG_PEAK);
        count  = Xil_In32(BEAM_BASE + REG_COUNT);

        peak &= 0x00FFFFFFU;

        leds = peak_to_leds(peak);

        Xil_Out32(GPIO_BASE + GPIO_DATA, leds);

        xil_printf(
            "CTRL=%08x STATUS=%08x PEAK=%08x "
            "COUNT=%u LED=%02x\r\n",
            (unsigned int)ctrl,
            (unsigned int)status,
            (unsigned int)peak,
            (unsigned int)count,
            (unsigned int)leds
        );

        usleep(UPDATE_US);

        ticks++;

        // Reset peak every 500 ms
        if (ticks >= RESET_TICKS)
        {
            ticks = 0;

            // Enable + clear_history pulse
            Xil_Out32(BEAM_BASE + REG_CTRL, 0x05U);

            // Keep beamformer enabled
            Xil_Out32(BEAM_BASE + REG_CTRL, 0x01U);
        }
    }

    return 0;
}
