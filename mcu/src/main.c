// =============================================================
// Integrated test: phase-quantized spectrum → 512-pt iFFT
// =============================================================

// Adjust these includes to match your project structure
#include "arm_math.h"
#include "arm_const_structs.h"
#include "main.h"

#include <math.h>
#include <stdint.h>
#include <string.h>
#include <stdio.h>

#define FFT_N             512
#define HALF_BINS         (FFT_N / 2)          // 256
#define NUM_PHASE_LEVELS  16                   // phase buckets
#define AUDIO_SCALE       (1.0f / 32768.0f)    // convert int16 -> float

#ifndef PI_F
#define PI_F 3.14159265358979323846f
#endif

// ------------------------
// Buffers
// ------------------------

// Fake FPGA frame: 256 complex bins (0..255) * 4 bytes per bin = 1024 bytes
static uint8_t  spi_rx_test[1024];

// Full 512-point complex spectrum (interleaved Re,Im) → also used as iFFT buffer
static float32_t X_full_test[2 * FFT_N];


// =============================================================
// Phase quantization + Hermitian reconstruction
// =============================================================
void fft_postprocess_phase_quantize(const uint8_t *spi_rx, float32_t *X_full)
{
    const float32_t phase_step = 2.0f * PI_F / NUM_PHASE_LEVELS;

    // Step 0: Clear output buffer
    for (int i = 0; i < 2 * FFT_N; i++) {
        X_full[i] = 0.0f;
    }

    // Step 1: DC bin (k = 0): real only
    {
        int16_t r0 = (int16_t)(((uint16_t)spi_rx[0] << 8) | spi_rx[1]);
        X_full[0] = (float32_t)r0 * AUDIO_SCALE;  // Re[0]
        X_full[1] = 0.0f;                         // Im[0]
    }

    // Step 2: Bins 1..254 (general complex bins)
    for (int k = 1; k < HALF_BINS - 1; k++) {

        uint16_t base = 4 * k;

        int16_t real16 = (int16_t)(((uint16_t)spi_rx[base + 0] << 8) | spi_rx[base + 1]);
        int16_t imag16 = (int16_t)(((uint16_t)spi_rx[base + 2] << 8) | spi_rx[base + 3]);

        float32_t Re = (float32_t)real16 * AUDIO_SCALE;
        float32_t Im = (float32_t)imag16 * AUDIO_SCALE;

        float32_t mag = sqrtf(Re * Re + Im * Im);
        float32_t phi = atan2f(Im, Re);

        // Step 3: Quantize phase to nearest multiple of phase_step
        float32_t phi_q = phase_step * roundf(phi / phase_step);

        float32_t sin_phi, cos_phi;
        arm_sin_cos_f32(phi_q, &sin_phi, &cos_phi);

        Re = mag * cos_phi;
        Im = mag * sin_phi;

        X_full[2 * k]     = Re;
        X_full[2 * k + 1] = Im;
    }

    // Step 4: Bin 255: treat as real-only
    {
        int k = HALF_BINS - 1;   // 255
        uint16_t base = 4 * k;

        int16_t real16 = (int16_t)(((uint16_t)spi_rx[base + 0] << 8) | spi_rx[base + 1]);
        X_full[2 * k]     = (float32_t)real16 * AUDIO_SCALE;
        X_full[2 * k + 1] = 0.0f;
    }

    // Step 5: Nyquist bin (k = 256) is not sent → set to 0
    X_full[2 * HALF_BINS]     = 0.0f;   // Re[256]
    X_full[2 * HALF_BINS + 1] = 0.0f;   // Im[256]

    // Step 6: Rebuild upper half 257..511 via Hermitian symmetry
    for (int k = 1; k < HALF_BINS; k++) {
        int k_mirror = FFT_N - k;  // 511..257

        float32_t Re_k = X_full[2 * k];
        float32_t Im_k = X_full[2 * k + 1];

        X_full[2 * k_mirror]     =  Re_k;
        X_full[2 * k_mirror + 1] = -Im_k;    // conjugate
    }
}


// =============================================================
// Fake FFT frame generator (for testing)
// Only bin k=10 is nonzero (real = 10000, imag = 0)
// =============================================================
static void fill_fake_fft_frame(void)
{
    memset(spi_rx_test, 0, sizeof(spi_rx_test));

    int      k      = 10;
    uint16_t base   = 4 * k;
    int16_t  real16 = 10000;
    int16_t  imag16 = 0;

    spi_rx_test[base + 0] = (uint8_t)((real16 >> 8) & 0xFF);  // real MSB
    spi_rx_test[base + 1] = (uint8_t)( real16       & 0xFF);  // real LSB
    spi_rx_test[base + 2] = (uint8_t)((imag16 >> 8) & 0xFF);  // imag MSB
    spi_rx_test[base + 3] = (uint8_t)( imag16       & 0xFF);  // imag LSB
}


// =============================================================
// iFFT: take 512-point complex spectrum in-place (float32)
// and produce time-domain signal (still interleaved Re,Im).
// This is your "runInverseFFT512", adapted to use X_full_test.
// =============================================================
void runInverseFFT512_fromSpectrum(float32_t *buf)
{
    // buf has 1024 floats: [Re0, Im0, Re1, Im1, ..., Re511, Im511]
    const arm_cfft_instance_f32 *cfft = &arm_cfft_sR_f32_len512;

    // ifftFlag = 1 → inverse FFT
    // bitReverseFlag = 1 → output in correct order
    arm_cfft_f32(cfft, buf, 1, 1);

    // Normalize by N if your CMSIS version doesn't
    arm_scale_f32(buf, 1.0f / (float32_t)FFT_N, buf, 2 * FFT_N);
}


// =============================================================
// Debug print helpers
// =============================================================
static void print_some_spectrum(const float32_t *X, int k_test)
{
    int k_mirror = FFT_N - k_test;

    printf("\n=== PHASE QUANT TEST (SPECTRUM) ===\n");

    // DC bin
    printf("DC bin (k=0):\n");
    printf("  Re[0] = %f\n", X[0]);
    printf("  Im[0] = %f\n", X[1]);

    // Chosen active bin
    printf("\nBin %d:\n", k_test);
    printf("  Re[%d] = %f\n", k_test, X[2 * k_test]);
    printf("  Im[%d] = %f\n", k_test, X[2 * k_test + 1]);

    // Mirror bin
    printf("\nMirror bin %d:\n", k_mirror);
    printf("  Re[%d] = %f\n", k_mirror, X[2 * k_mirror]);
    printf("  Im[%d] = %f\n", k_mirror, X[2 * k_mirror + 1]);
}

static void print_time_domain(const float32_t *x, int num_samples)
{
    printf("\n=== IFFT OUTPUT (TIME DOMAIN, first %d samples) ===\n", num_samples);
    for (int n = 0; n < num_samples; n++) {
        float32_t re = x[2 * n];
        float32_t im = x[2 * n + 1];
        printf("x[%3d] = %f + j%f\n", n, re, im);
    }
}


// =============================================================
// main()
// =============================================================
int main(void)
{
    configureFlash();
    configureClock();
    gpioEnable(GPIO_PORT_A);
    gpioEnable(GPIO_PORT_B);
    gpioEnable(GPIO_PORT_C);
  
    RCC->APB2ENR |= (RCC_APB2ENR_TIM15EN);
    initTIM(TIM15);
    int k_test = 10;

    // 1) Build fake FPGA FFT frame
    fill_fake_fft_frame();

    // 2) Run phase quantization + Hermitian reconstruction
    fft_postprocess_phase_quantize(spi_rx_test, X_full_test);

    // 3) Debug: print some of the spectrum (after pitch correction)
    print_some_spectrum(X_full_test, k_test);

    // 4) Run 512-point inverse FFT directly on X_full_test
    runInverseFFT512_fromSpectrum(X_full_test);

    // 5) Debug: print iFFT output samples
    print_time_domain(X_full_test, 32);   // first 32 time-domain samples

    // On MCU you might replace this with while(1) { ... }
    while (1) {
        // idle
    }

    return 0;
}
