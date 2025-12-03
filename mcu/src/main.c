#include "arm_math.h"
#include "arm_const_structs.h"
#include <string.h>

// ---------------------------------------------------------
// 1) Input: 1024 integers (re0, im0, re1, im1, ..., re511, im511)
// ---------------------------------------------------------
int16_t inputInt16[1024];   // Fill this with your data

// ---------------------------------------------------------
// 2) Working buffers
// ---------------------------------------------------------
float32_t fftInputF32[1024];
float32_t fftOutputF32[1024];


// ---------------------------------------------------------
// Convert int16 → float32 and run 512-point inverse FFT
// ---------------------------------------------------------
void runInverseFFT512(void)
{
    // ----- Step 1: Convert INT16 → FLOAT32 -----
    for (int i = 0; i < 1024; i++)
    {
        fftInputF32[i] = (float32_t)inputInt16[i];
    }

    // Copy input to output (CMSIS FFT is in-place)
    memcpy(fftOutputF32, fftInputF32, sizeof(fftInputF32));

    // ----- Step 2: Select CMSIS 512-Point CFFT -----
    const arm_cfft_instance_f32 *cfft = &arm_cfft_sR_f32_len512;

    // ----- Step 3: Run inverse FFT -----
    // ifftFlag = 1 → inverse FFT
    // bitReverseFlag = 1 → correct output ordering
    arm_cfft_f32(cfft, fftOutputF32, 1, 1);

    // ----- Step 4: Optional: normalize by N = 512 -----
    // Many CMSIS versions do NOT normalize the IFFT automatically.
    // Enable this if your output looks ~512x too large.
    arm_scale_f32(fftOutputF32, 1.0f/512.0f, fftOutputF32, 1024);

    // fftOutputF32 now contains time-domain samples:
    // fftOutputF32[0] = x(0)
    // fftOutputF32[1] = imag residue (should be ~0)
    // fftOutputF32[2] = x(1)
    // ...
}


// ---------------------------------------------------------
// Example main()
// ---------------------------------------------------------
int main(void)
{
    HAL_Init();
    SystemClock_Config();   // Your clock setup

    // ---- Fill inputInt16[] with your FFT frequency data here ----
    // Example:
    // inputInt16[0] = re0;
    // inputInt16[1] = im0;
    // inputInt16[2] = re1;
    // inputInt16[3] = im1;
    // ...


    runInverseFFT512();

    // Now fftOutputF32[] holds real time-domain values
    // Imaginary parts should be nearly zero.


    while (1)
    {
        // Do something with the result...
    }
}
