// need some sort of voltage to frequency function and a frequency to voltage

#include "arm_math.h"   // CMSIS-DSP: arm_sin_cos_f32, etc.
#include <math.h>
#include <stdint.h>

#define FFT_N             512
#define HALF_BINS         (FFT_N / 2)      // 256
#define NUM_PHASE_LEVELS  16               // number of phase buckets
#define AUDIO_SCALE       (1.0f / 128.0f)  // scale factor to convert 8-bit signed integers into float values

#ifndef PI_F
#define PI_F 3.14159265358979323846f
#endif

/**
 * spi_rx : 512 bytes from FPGA over SPI. Each FFT bin k is packed as:
 *  spi_rx[2*k]   = real8
 *  spi_rx[2*k+1] = imag8
 *
 * X_full : output array holding a full 512-point complex spectrum in alternating format:
 *  X_full[2*k]   = Re[k]
 *  X_full[2*k+1] = Im[k]
 *
 * After running this function:
 *  - The phases have been quantized ("pitch correction")
 *  - The full 512-point Hermitian spectrum is rebuilt
 *  - The array is ready for a CMSIS 512-point complex iFFT
 */

void fft_postprocess_phase_quantize(const uint8_t *spi_rx, float *X_full)
{
    const float phase_step = 2.0f * PI_F / NUM_PHASE_LEVELS;

    // Step 0: Clearing the output buffer
    for (int i = 0; i < 2 * FFT_N; i++) {
        X_full[i] = 0.0f;
    }

    // Step 1: Handle DC bin (bin 0) to take the real part and ignore the imaginary noise
    {
        int8_t r0 = (int8_t)spi_rx[0];

        X_full[0] = (float)r0 * AUDIO_SCALE;  // Re[0]
        X_full[1] = 0.0f;                     // Im[0]
    }

    // Step 2: Unpack bins 1..254 and convert them to floats. Then, compute magnitude + phase
    for (int k = 1; k < HALF_BINS - 1; k++) {

        // Unpack raw 8-bit real & imag from FPGA frame
        int8_t real8 = (int8_t)spi_rx[2 * k];
        int8_t imag8 = (int8_t)spi_rx[2 * k + 1];

        // Convert to float values
        float Re = (float)real8 * AUDIO_SCALE;
        float Im = (float)imag8 * AUDIO_SCALE;

        // Compute magnitude and phase
        float mag = sqrtf((Re * Re) + (Im * Im));
        float phi = atan2f(Im, Re);

    // Step 3: Quantize the phase by spapping phi to the nearest multiple of phase_step
        float phi_q = phase_step * roundf(phi / phase_step);

        // Convert back to complex using same magnitude
        float sin_phi
        float cos_phi;
        arm_sin_cos_f32(phi_q, &sin_phi, &cos_phi); // function to store sin and cos of phi

        Re = mag * cos_phi;
        Im = mag * sin_phi;

        // Store quantized bin in lower half of spectrum
        X_full[2 * k] = Re;
        X_full[2 * k + 1] = Im;
    }

    // Step 4: Handle bin 255 (treated as real-only)
    {
        int k = HALF_BINS - 1; // 255
        int8_t real8 = (int8_t)spi_rx[2 * k];

        X_full[2 * k] = (float)real8 * AUDIO_SCALE;
        X_full[2 * k + 1] = 0.0f;
    }

    // Step 5: Define Nyquist bin (bin 256). We don't receive it, because FPGA only sends 
    // 0 to 255 bins, so set bin 256 = 0.
    X_full[2 * HALF_BINS]     = 0.0f;  // Re[256]
    X_full[2 * HALF_BINS + 1] = 0.0f;  // Im[256]

    // Step 6: Rebuild upper half of the 512-point FFT using Hermitian symmetry:
    //   X[k_mirror] = conj( X[k] ), where k_mirror = 512 - k.
    // This produces bins 257..511.
    for (int k = 1; k < HALF_BINS; k++) {
        int k_mirror = FFT_N - k;  // 511..257

        // Reading the real and imaginary parts of the lower half bin
        float Re_k = X_full[2 * k];
        float Im_k = X_full[2 * k + 1];

        // Writing conjugate symmetric bin into upper half
        X_full[2 * k_mirror]  =  Re_k;
        X_full[2 * k_mirror + 1] = -Im_k;
    }
}

