// signal_processing.h
// Header for signal processing functions
// Emma Angel
// eangel@hmc.edu
// 12/5/2025

#include <stdint.h>
#include "stm32l4xx.h"
#include "arm_math.h"
#include "arm_const_structs.h"
#include <stdint.h>
#include <string.h>
#include <stdio.h>
#include <math.h>

#define FFT_N              64
#define HALF_BINS          (FFT_N/2)     // 32
#define NUM_PHASE_LEVELS   16
#define AUDIO_SCALE        (1.0f / 32768.0f)

// Overlap-add buffer
#define OUTBUF_SIZE 2048
#define HOP         (FFT_N/4)   // 16-sample hop
#define PI_F        3.14159265358979323846f

/** -------------------------------------------------------------------------

* @brief  Converts raw SPI FFT-bin data into a full 64-point complex spectrum
* ```
      with phase quantization and Hermitian reconstruction.  
  ```
*
* This function parses 16-bit real/imaginary FFT bin values received over SPI,
* rescales them, quantizes the phase of each positive-frequency bin to the
* nearest of NUM_PHASE_LEVELS discrete angles, and reconstructs the complex
* spectrum so it can be fed to an inverse FFT.
*
* Processing steps:
* * Clear the output spectrum buffer X (size 2*FFT_N).
* * Read the DC bin and Nyquist bin.
* * Process bins 1–31: convert to float, compute magnitude & phase,
* quantize the phase, then reconstruct Re/Im values.
* * Rebuild negative-frequency bins (Hermitian symmetry) for IFFT use.
*
* @param spi_rx  Pointer to the raw SPI buffer containing 16-bit bin data.
* @param X       Output buffer holding complex FFT samples as interleaved
* ```
             float32_t values: X[2*k] = real, X[2*k+1] = imag.  
  ```
* ---

*/
void fft_postprocess_phase_quantize_64(const uint8_t *spi_rx, float32_t *X)
{
...
}

/** -------------------------------------------------------------------------

* @brief  Performs a 64-point inverse FFT on an interleaved complex buffer.
*
* Uses CMSIS-DSP to run the inverse FFT (bit-reversal + IFFT stages), then
* scales the result by 1/FFT_N to obtain the correct time-domain amplitude.
*
* @param X  Pointer to a 64-point complex array (interleaved Re/Im) that will
* ```
        be overwritten with the time-domain output samples.  
  ```
* ---

*/
void run_ifft_64(float32_t *X)
{
...
}

/** -------------------------------------------------------------------------

* @brief  Precomputes a 64-point Hann window and stores it in hann_win[].
*
* The Hann window is defined as:
* w[n] = 0.5 − 0.5*cos(2πn / (N−1))
*
* This is used during overlap-add synthesis to smooth block boundaries and
* avoid discontinuities in the reconstructed audio signal.
* ---

*/
void init_hann_64(void)
{
...
}

/** -------------------------------------------------------------------------

* @brief  Applies Hann windowing, performs overlap-add, clips/scales samples,
* ```
      and outputs the reconstructed audio frame to the DAC.  
  ```
*
* This function is called once per IFFT output frame.
* Steps performed:
* * Multiply each complex IFFT output sample by the Hann window.
* * Add windowed samples into the circular overlap-add buffer.
* * Convert accumulated samples to DAC voltage (scaled 0–5 V).
* * Clip the signal to the DAC's valid range.
* * Output each sample to the DAC using setDAC().
* * Advance the overlap-add write pointer by HOP.
*
* @param X  Complex IFFT output buffer, length = 64 samples stored
* ```
        in interleaved real/imag format (only real part is used).  
  ```
* ---

*/
void process_ifft_frame_and_output(float32_t *X)
{
...
}