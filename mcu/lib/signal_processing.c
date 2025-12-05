// signal_processing.c
// Source for signal processing functions
// Emma Angel
// eangel@hmc.edu
// 12/5/2025

#include "signal_processing.h"

void fft_postprocess_phase_quantize_64(const uint8_t *spi_rx, float32_t *X)
{
    const float32_t step = 2.0f * PI_F / NUM_PHASE_LEVELS;

    // Clear output buffer
    for (int i = 0; i < 2*FFT_N; i++)
        X[i] = 0.0f;

    // DC bin = k=0
    int16_t dc_val = (int16_t)((spi_rx[0] << 8) | spi_rx[1]);
    X[0] = dc_val * AUDIO_SCALE;
    X[1] = 0.0f;

    // Bins 1..31 = positive frequencies
    for (int k = 1; k < HALF_BINS; k++)
    {
        uint16_t idx = 4*k;

        int16_t Re16 = (int16_t)((spi_rx[idx] << 8) | spi_rx[idx+1]);
        int16_t Im16 = (int16_t)((spi_rx[idx+2] << 8) | spi_rx[idx+3]);

        float32_t Re = Re16 * AUDIO_SCALE;
        float32_t Im = Im16 * AUDIO_SCALE;

        float32_t mag = sqrtf(Re*Re + Im*Im);
        float32_t phi = atan2f(Im, Re);

        float32_t phi_q = step * roundf(phi / step);

        float32_t s, c;
        arm_sin_cos_f32(phi_q, &s, &c);

        X[2*k]   = mag * c;
        X[2*k+1] = mag * s;
    }

    // Nyquist bin = k=32 → must be purely real
    int16_t ny_re = (int16_t)((spi_rx[4*HALF_BINS] << 8) |
                               spi_rx[4*HALF_BINS + 1]);
    X[2*HALF_BINS]     = ny_re * AUDIO_SCALE;
    X[2*HALF_BINS + 1] = 0.0f;

    // Negative bins reconstruction: k=33..63
    for (int k = 1; k < HALF_BINS; k++)
    {
        int kp = FFT_N - k;
        X[2*kp]     =  X[2*k];
        X[2*kp + 1] = -X[2*k + 1];
    }
}
void run_ifft_64(float32_t *X)
{
    const arm_cfft_instance_f32 *cfft = &arm_cfft_sR_f32_len64;

    arm_cfft_f32(cfft, X, 1, 1);  // inverse FFT
    arm_scale_f32(X, 1.0f/FFT_N, X, 2*FFT_N);
}
void init_hann_64(void)
{
    for (int n = 0; n < FFT_N; n++)
    {
        hann_win[n] =
            0.5f - 0.5f * arm_cos_f32(2.0f * PI_F * n / (FFT_N - 1));
    }
}
void process_ifft_frame_and_output(float32_t *X)
{
    configureDAC();  // switch SPI into DAC mode

    for (int n = 0; n < FFT_N; n++)
    {
        float32_t s = X[2*n] * hann_win[n];

        uint32_t idx = (ola_pos + n) % OUTBUF_SIZE;
        ola_buffer[idx] += s;

        float32_t v = ola_buffer[idx] * 40000.0f;

        if (v < 0.0f) v = 0.0f;
        if (v > 5.0f) v = 5.0f;

        setDAC(v);
    }

    ola_pos = (ola_pos + HOP) % OUTBUF_SIZE;
}