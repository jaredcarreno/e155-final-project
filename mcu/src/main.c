// need some sort of voltage to frequency function and a frequency to voltage

#include "arm_math.h"   // CMSIS-DSP: arm_sin_cos_f32, etc.
#include <math.h>
#include <stdint.h>
#include <string.h>   // for memset

#define FFT_N             512
#define HALF_BINS         (FFT_N / 2)      // 256
#define NUM_PHASE_LEVELS  16               // number of phase buckets
#define AUDIO_SCALE       (1.0f / 32768.0f)  // scale factor to convert 16-bit signed integers into float values

#ifndef PI_F
#define PI_F 3.14159265358979323846f
#endif


/**
 * spi_rx : 1024 bytes from FPGA over SPI. Each FFT bin k is packed as a 32-bit word:   
 *  [4*k + 0] = real16 MSB                                                               
 *  [4*k + 1] = real16 LSB                                                               
 *  [4*k + 2] = imag16 MSB                                                               
 *  [4*k + 3] = imag16 LSB 
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
       // real16 is in bytes [0] (MSB) and [1] (LSB)
        int16_t r0 = (int16_t)(((uint16_t)spi_rx[0] << 8) | spi_rx[1]);

        X_full[0] = (float)r0 * AUDIO_SCALE;  // Re[0]
        X_full[1] = 0.0f;                     // Im[0]
    }

    // Step 2: Unpack bins 1..254 and convert them to floats. Then, compute magnitude + phase
    for (int k = 1; k < HALF_BINS - 1; k++) {

        // Unpack raw 16-bit real & imag from FPGA frame 
        uint16_t base = 4 * k; 
        int16_t real16 = (int16_t)(((uint16_t)spi_rx[base] << 8) | spi_rx[base + 1]);  
        int16_t imag16 = (int16_t)(((uint16_t)spi_rx[base + 2] << 8) | spi_rx[base + 3]); 

        // Convert to float values
        float Re = (float)real16 * AUDIO_SCALE;  
        float Im = (float)imag16 * AUDIO_SCALE;

        // Compute magnitude and phase
        float mag = sqrtf((Re * Re) + (Im * Im));
        float phi = atan2f(Im, Re);

    // Step 3: Quantize the phase by spapping phi to the nearest multiple of phase_step
        float phi_q = phase_step * roundf(phi / phase_step);

        // Convert back to complex using same magnitude
        float sin_phi;
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

        // real16 for bin 255 is at bytes [4*k] and [4*k+1]                         
        uint16_t base = 4 * k;                                        
        int16_t real16 = (int16_t)(((uint16_t)spi_rx[base] << 8) | spi_rx[base + 1]); 

        X_full[2 * k] = (float)real16 * AUDIO_SCALE;
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



// FOR TESTING THE PHASE QUANTIZATION

static uint8_t spi_rx_test[1024];        // fake FPGA frame
static float   X_full_test[2 * FFT_N];   // output spectrum

// Fill spi_rx_test with a simple known pattern: e.g. only bin 10 nonzero
static void fill_fake_fft_frame(void)
{
    memset(spi_rx_test, 0, sizeof(spi_rx_test));

    int k = 10;                  // choose some bin
    uint16_t base = 4 * k;
    int16_t real16 = 10000;      // arbitrary non-zero magnitude
    int16_t imag16 = 0;

    spi_rx_test[base + 0] = (uint8_t)((real16 >> 8) & 0xFF);  // real MSB
    spi_rx_test[base + 1] = (uint8_t)( real16       & 0xFF);  // real LSB
    spi_rx_test[base + 2] = (uint8_t)((imag16 >> 8) & 0xFF);  // imag MSB
    spi_rx_test[base + 3] = (uint8_t)( imag16       & 0xFF);  // imag LSB

}

int main(void)
{

    fill_fake_fft_frame();

    fft_postprocess_phase_quantize(spi_rx_test, X_full_test);

    while (1) 
    { 

    }
}