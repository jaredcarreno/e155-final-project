// =============================================================
// Integrated test: spectrum → IFFT → real-time reconstruction
// with Hann window + overlap-add + DAC output
// =============================================================

#include "arm_math.h"
#include "arm_const_structs.h"
#include "main.h"

#include <math.h>
#include <stdint.h>
#include <string.h>
#include <stdio.h>

#define FFT_N             512
#define HALF_BINS         (FFT_N / 2)
#define NUM_PHASE_LEVELS  16
#define AUDIO_SCALE       (1.0f / 32768.0f)

#define HOP               (FFT_N / 4)      // 75% overlap
#define OUTBUF_SIZE       8192             // big enough output ring buffer

#ifndef PI_F
#define PI_F 3.14159265358979323846f
#endif

// ------------------------
// Buffers
// ------------------------
static uint8_t    spi_rx_test[1024];
static float32_t  X_full_test[2 * FFT_N];

// ===== ADDED: STFT RECONSTRUCTION BUFFERS =====
static float32_t  hann_win[FFT_N];
static float32_t  ola_buffer[OUTBUF_SIZE];
static uint32_t   ola_write_pos = 0;


// =============================================================
// (your existing phase quantization function — unchanged)
// =============================================================
void fft_postprocess_phase_quantize(const uint8_t *spi_rx, float32_t *X_full)
{
    const float32_t phase_step = 2.0f * PI_F / NUM_PHASE_LEVELS;

    for (int i = 0; i < 2 * FFT_N; i++)
        X_full[i] = 0.0f;

    int16_t r0 = (int16_t)(((uint16_t)spi_rx[0] << 8) | spi_rx[1]);
    X_full[0] = (float32_t)r0 * AUDIO_SCALE;
    X_full[1] = 0.0f;

    for (int k = 1; k < HALF_BINS - 1; k++) {

        uint16_t base = 4 * k;

        int16_t real16 = (int16_t)(((uint16_t)spi_rx[base + 0] << 8) | spi_rx[base + 1]);
        int16_t imag16 = (int16_t)(((uint16_t)spi_rx[base + 2] << 8) | spi_rx[base + 3]);

        float32_t Re = (float32_t)real16 * AUDIO_SCALE;
        float32_t Im = (float32_t)imag16 * AUDIO_SCALE;

        float32_t mag = sqrtf(Re*Re + Im*Im);
        float32_t phi = atan2f(Im, Re);

        float32_t phi_q = phase_step * roundf(phi / phase_step);
        float32_t sin_phi, cos_phi;
        arm_sin_cos_f32(phi_q, &sin_phi, &cos_phi);

        X_full[2*k]     = mag * cos_phi;
        X_full[2*k + 1] = mag * sin_phi;
    }

    int k = HALF_BINS - 1;  
    uint16_t base = 4 * k;
    int16_t real16 = (int16_t)(((uint16_t)spi_rx[base + 0] << 8) | spi_rx[base + 1]);
    X_full[2*k]     = (float32_t)real16 * AUDIO_SCALE;
    X_full[2*k + 1] = 0.0f;

    X_full[2 * HALF_BINS]     = 0.0f;
    X_full[2 * HALF_BINS + 1] = 0.0f;

    for (int k = 1; k < HALF_BINS; k++) {
        int k_mirror = FFT_N - k;
        X_full[2*k_mirror]     =  X_full[2*k];
        X_full[2*k_mirror + 1] = -X_full[2*k + 1];
    }
}


// =============================================================
// Fake FFT generator (unchanged)
// =============================================================
static void fill_fake_fft_frame(void)
{
    memset(spi_rx_test, 0, sizeof(spi_rx_test));

    int16_t real16 = 30000;    // VERY LARGE NON-ZERO VALUE

    // DC bin = bin 0 → first 2 bytes are real value, next 2 bytes imaginary
    spi_rx_test[0] = (real16 >> 8) & 0xFF;
    spi_rx_test[1] = (real16      ) & 0xFF;

    // imaginary = 0
    spi_rx_test[2] = 0;
    spi_rx_test[3] = 0;
}


//static void fill_fake_fft_frame(void)
//{
//    memset(spi_rx_test, 0, sizeof(spi_rx_test));

//    int k = 10;
//    int16_t real16 = 10000;
//    int16_t imag16 = 0;

//    spi_rx_test[4*k + 0] = (real16 >> 8) & 0xFF;
//    spi_rx_test[4*k + 1] = (real16      ) & 0xFF;
//    spi_rx_test[4*k + 2] = (imag16 >> 8) & 0xFF;
//    spi_rx_test[4*k + 3] = (imag16      ) & 0xFF;
//}


// =============================================================
// 512-pt IFFT
// =============================================================
void runInverseFFT512_fromSpectrum(float32_t *buf)
{
    const arm_cfft_instance_f32 *cfft = &arm_cfft_sR_f32_len512;
    arm_cfft_f32(cfft, buf, 1, 1);
    arm_scale_f32(buf, 1.0f / FFT_N, buf, 2 * FFT_N);
}


// =============================================================
// ===== ADDED: Initialize Hann window =====
// =============================================================
void initHann(void)
{
    for (int n = 0; n < FFT_N; n++)
    {
        hann_win[n] = 0.5f - 0.5f * arm_cos_f32(2.0f * PI_F * n / (FFT_N - 1));
    }
}


// =============================================================
// ===== ADDED: Overlap-add reconstruction + DAC output =====
// =============================================================
void process_frame_and_output(float32_t *ifft_buf)
{
    // ifft_buf has: [Re0, Im0, Re1, Im1, ...]

    for (int n = 0; n < FFT_N; n++)
    {
        float32_t s = ifft_buf[2*n];         // real part
        s *= hann_win[n];                    // apply window

        uint32_t idx = (ola_write_pos + n) % OUTBUF_SIZE;
        ola_buffer[idx] += s;

        // Output to your external DAC (setDAC expects a voltage)
        // CONVERT float → voltage (scaled 0..1.0)
        // float32_t v = ola_buffer[idx];
        float32_t v = ola_buffer[idx] * 200000.0f;   // big boost
        if (v > 5.0f) v = 5.0f;
        if (v < 0.0f) v = 0.0f;
        printf("v[%d] = %f\n", n, v);   // DEBUG PRINT
        setDAC(v);
    }

    // move write pointer
    ola_write_pos = (ola_write_pos + HOP) % OUTBUF_SIZE;
}


// =============================================================
// main()
// =============================================================
int main(void)
{
    printf("MAIN START\n");
    configureFlash();
    configureClock();
    gpioEnable(GPIO_PORT_A);
    gpioEnable(GPIO_PORT_B);
    gpioEnable(GPIO_PORT_C);
  
    RCC->APB2ENR |= RCC_APB2ENR_TIM15EN;
    initTIM(TIM15);

    printf("After configs\n");

    configureDAC();

    memset(ola_buffer, 0, sizeof(ola_buffer));
    initHann();

    int k_test = 10;

    printf("After memset\n");

    initSPI(6, 0, 0);
    configureDAC();
    printf("Waiting\n");
    delay_millis(TIM15, 1000);


    while (1)
    {
        // 1) Build fake FFT from FPGA (for now)
        fill_fake_fft_frame();

        // delay_millis(TIM15, 100);
        printf("loop running\n");

        // 2) Apply phase quantization
        fft_postprocess_phase_quantize(spi_rx_test, X_full_test);

        // 3) Run IFFT
        runInverseFFT512_fromSpectrum(X_full_test);

        // 4) Window + overlap-add + DAC output
        printf("process start\n");
        process_frame_and_output(X_full_test);
        printf("process end\n");



        // NOTE: real system should wait for next FFT frame:
        // e.g., poll SPI ready, DMA complete, interrupt, etc.
    }

    return 0;
}
