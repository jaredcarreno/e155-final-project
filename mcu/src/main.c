#include "arm_math.h"
#include "arm_const_structs.h"
#include "main.h"

#include <math.h>
#include <stdint.h>
#include <string.h>
#include <stdio.h>

// =============================================================
// Config
// =============================================================

#define SAMPLE_RATE       16000.0f

#define FFT_N             512
#define HALF_BINS         (FFT_N / 2)
#define NUM_PHASE_LEVELS  16
#define AUDIO_SCALE       (1.0f / 32768.0f)

#define HOP               (FFT_N / 4)      // 75% overlap
#define OUTBUF_SIZE       8192            // big enough output ring buffer

#ifndef PI_F
#define PI_F 3.14159265358979323846f
#endif

// ------------------------
// Buffers
// ------------------------
static uint8_t    spi_rx_test[2048];
static float32_t  X_full_test[2 * FFT_N];

static float32_t  hann_win[FFT_N];
static float32_t  ola_buffer[OUTBUF_SIZE];
static uint32_t   ola_write_pos = 0;
// =============================================
// Audio buffer shared with ISR (Option B system)
// =============================================
#define BUFFER_SIZE 4096   // or 8192 if RAM allows

static float32_t audio_buffer[BUFFER_SIZE];
static volatile uint32_t audio_r = 0;   // ISR reads
static volatile uint32_t audio_w = 0;   // main writes


// =============================================================
// Your existing phase quantization function — UNCHANGED
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

    for (int k2 = 1; k2 < HALF_BINS; k2++) {
        int k_mirror = FFT_N - k2;
        X_full[2*k_mirror]     =  X_full[2*k2];
        X_full[2*k_mirror + 1] = -X_full[2*k2 + 1];
    }
}

// =============================================================
// Fake FFT generator — use your original working k-bin version
// (this is the one you had commented out)
// =============================================================
static void fill_fake_fft_frame(void)
{
    memset(spi_rx_test, 0, sizeof(spi_rx_test));

    int k = 10;
    int16_t real16 = 10000;
    int16_t imag16 = 0;

    spi_rx_test[4*k + 0] = (real16 >> 8) & 0xFF;
    spi_rx_test[4*k + 1] = (real16      ) & 0xFF;
    spi_rx_test[4*k + 2] = (imag16 >> 8) & 0xFF;
    spi_rx_test[4*k + 3] = (imag16      ) & 0xFF;
}


// =============================================================
// 512-pt IFFT — UNCHANGED
// =============================================================
void runInverseFFT512_fromSpectrum(float32_t *buf)
{
    const arm_cfft_instance_f32 *cfft = &arm_cfft_sR_f32_len512;
    arm_cfft_f32(cfft, buf, 1, 1);
    arm_scale_f32(buf, 1.0f / FFT_N, buf, 2 * FFT_N);
}

// =============================================================
// Hann window init — UNCHANGED
// =============================================================
void initHann(void)
{
    for (int n = 0; n < FFT_N; n++)
    {
        hann_win[n] = 0.5f - 0.5f * arm_cos_f32(2.0f * PI_F * n / (FFT_N - 1));
    }
}

// =============================================================
// Overlap-add reconstruction + DAC output (your original pattern)
// =============================================================
static inline void audio_push(float32_t s)
{
    audio_buffer[audio_w] = s;
    audio_w = (audio_w + 1) % BUFFER_SIZE;
}

void process_frame_and_push(float32_t *ifft_buf)
{
    for (int n = 0; n < FFT_N; n++)
    {
        // float32_t s = ifft_buf[2*n] * hann_win[n];   // real IFFT sample
        float32_t s = ifft_buf[2*n] * hann_win[n] * 2000.0f;
        printf("OLA sample: %f\n", s);

        uint32_t idx = (ola_write_pos + n) % BUFFER_SIZE;

        // True overlap-add
        ola_buffer[idx] += s;

        // Send overlapped sample to ISR audio buffer
        audio_push(ola_buffer[idx]);

        // Critical: clear so OLA doesn't accumulate infinitely
        ola_buffer[idx] = 0.0f;
    }

    ola_write_pos = (ola_write_pos + HOP) % BUFFER_SIZE;
}


void TIM2_IRQHandler(void)
{
    if (TIM2->SR & TIM_SR_UIF)
    {
        TIM2->SR &= ~TIM_SR_UIF;   // IMPORTANT: clear interrupt

        // printf("ISR firing...\n");

        float32_t s = audio_buffer[audio_r];
        audio_r = (audio_r + 1) % BUFFER_SIZE;

        float32_t v = 2.5f + 1.0f * s;
        if (v < 0.0f) v = 0.0f;
        if (v > 5.0f) v = 5.0f;

        // printf("DAC voltage set: %f\n", v);

        setDAC(v);
    }
}


void initTIM2_16kHz(void)
{
    // Enable clock
    RCC->APB1ENR1 |= RCC_APB1ENR1_TIM2EN;

    // Your known-good settings:
    TIM2->PSC = 1;        // OK
    TIM2->ARR = 999;      // OK

    TIM2->CNT = 0;        // MUST reset the counter
    TIM2->DIER |= TIM_DIER_UIE;

    NVIC->ISER[0] |= (1 << TIM2_IRQn);

    TIM2->CR1 |= TIM_CR1_CEN;
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

    printf("System configured\n");

    // Delay timer first (used by everything else)
    RCC->APB2ENR |= RCC_APB2ENR_TIM15EN;
    initTIM(TIM15);

    // DAC must be configured before audio system starts
    configureDAC();

    // Init DSP buffers
    memset(ola_buffer, 0, sizeof(ola_buffer));
    initHann();

    // NOW — and ONLY NOW — start TIM2
    initTIM2_16kHz();
    printf("TIM2 started\n");

    __enable_irq();
    printf("IRQs enabled\n");

    while(1)
    {
        fill_fake_fft_frame();
        fft_postprocess_phase_quantize(spi_rx_test, X_full_test);
        runInverseFFT512_fromSpectrum(X_full_test);
        process_frame_and_push(X_full_test);
        printf("process\n");
    }
}


//// ================================================================
//// Combined Audio Output + FFT/IFFT + Phase Quantization Pipeline
//// STM32L432KC — TIM2 ISR for buffered audio output + main loop DAC
//// ================================================================

//#include "arm_math.h"
//#include "arm_const_structs.h"
//#include "main.h"
//#include <math.h>
//#include <stdint.h>
//#include <stdio.h>
//#include <string.h>

//// =============================
//// Audio Config
//// =============================
//#define SAMPLE_RATE     16000.0f
//#define HOP_SIZE        128
//#define FRAME_SIZE      512
//#define BUFFER_SIZE     4096

//#define PI_F            3.14159265358979f

//// =============================
//// DAC Mapping (unchanged)
//// =============================
//#define V_MID   2.5f
//#define V_AMP   1.0f
//#define V_MIN   0.0f
//#define V_MAX   5.0f

//// =============================
//// Audio ring buffer (ISR reads, main writes)
//// =============================
//static float32_t audio_buffer[BUFFER_SIZE];
//static volatile uint32_t audio_r = 0;
//static volatile uint32_t audio_w = 0;

//// ---------------------------------------------------------------
//// NEW: ISR → main-loop handoff for DAC SPI safety
//// ---------------------------------------------------------------
//volatile float32_t sample_to_dac = 0.0f;
//volatile uint8_t dac_update_flag = 0;

//// ================================================================
//// Sine table (unchanged — still generated, but not used)
//// ================================================================
//#define SINE_TABLE_SIZE 512
//static float32_t sine_table[SINE_TABLE_SIZE];

//// ================================================================
//// ▼ FFT/IFFT integration buffers (UNCHANGED)
//// ================================================================
//#define FFT_N             512
//#define HALF_BINS         (FFT_N / 2)
//#define NUM_PHASE_LEVELS  16
//#define AUDIO_SCALE       (1.0f / 32768.0f)
//#define HOP               (FFT_N / 4)

//static uint8_t    spi_rx_test[1024];
//static float32_t  X_full_test[2 * FFT_N];

//static float32_t  hann_win[FFT_N];          
//static float32_t  ola_buffer[BUFFER_SIZE];
//static uint32_t   ola_write_pos = 0;

//// ================================================================
//// Prototypes
//// ================================================================
//void initTIM2_16kHz(void);
//void generate_sine_table(void);

//// ================================================================
//// Generate sine table (original, unchanged)
//// ================================================================
//void generate_sine_table(void)
//{
//    for (int n = 0; n < SINE_TABLE_SIZE; n++)
//    {
//        float phase = 2.0f * PI_F * n / SINE_TABLE_SIZE;
//        sine_table[n] = sinf(phase);
//    }

//    printf("Sine table created: %.3f %.3f %.3f...\n",
//           sine_table[0], sine_table[1], sine_table[2]);
//}

//// ================================================================
//// Timer2 @ 16kHz (UNCHANGED except for DAC removal)
//// ================================================================
//void initTIM2_16kHz(void)
//{
//    RCC->APB1ENR1 |= RCC_APB1ENR1_TIM2EN;

//    TIM2->PSC = 8;     // same as before
//    TIM2->ARR = 999;

//    TIM2->CNT = 0;
//    TIM2->DIER |= TIM_DIER_UIE;
//    NVIC->ISER[0] |= (1 << TIM2_IRQn);
//    TIM2->CR1 |= TIM_CR1_CEN;
//}

//// ================================================================
//// ISR — NOW ONLY outputs sample *to main loop*, NOT SPI
//// ================================================================
//void TIM2_IRQHandler(void)
//{
//    if (TIM2->SR & TIM_SR_UIF)
//    {
//        TIM2->SR &= ~TIM_SR_UIF;

//        float32_t s = audio_buffer[audio_r];
//        audio_r = (audio_r + 1) % BUFFER_SIZE;

//        float32_t v = V_MID + V_AMP * s;
//        if (v < V_MIN) v = V_MIN;
//        if (v > V_MAX) v = V_MAX;

//        // ---------------------------------------------
//        // NEW: Hand off sample to main loop (SPI-safe)
//        // ---------------------------------------------
//        sample_to_dac = v;
//        dac_update_flag = 1;
//    }
//}

//// ================================================================
//// Push one sample into audio buffer (UNCHANGED)
//// ================================================================
//static inline void audio_push(float32_t s)
//{
//    audio_buffer[audio_w] = s;
//    audio_w = (audio_w + 1) % BUFFER_SIZE;
//}

//// ================================================================
//// FFT Hann init (UNCHANGED)
//// ================================================================
//void initHann(void)
//{
//    for (int n = 0; n < FFT_N; n++)
//    {
//        hann_win[n] =
//            0.5f - 0.5f * arm_cos_f32(2.0f * PI_F * n / (FFT_N - 1));
//    }
//}

//// ================================================================
//// Fake FFT sine generator (UNCHANGED)
//// ================================================================
//void fill_fake_fft_frame_sine(float freq_hz)
//{
//    memset(spi_rx_test, 0, sizeof(spi_rx_test));

//    int k = (int)((freq_hz * FFT_N) / SAMPLE_RATE);
//    if (k <= 0 || k >= FFT_N/2) return;

//    int16_t real = 16000;
//    int16_t imag = 0;

//    uint16_t base = 4 * k;
//    spi_rx_test[base + 0] = (real >> 8) & 0xFF;
//    spi_rx_test[base + 1] = (real     ) & 0xFF;
//    spi_rx_test[base + 2] = (imag >> 8) & 0xFF;
//    spi_rx_test[base + 3] = (imag     ) & 0xFF;

//    int km = FFT_N - k;
//    uint16_t base_m = 4 * km;
//    spi_rx_test[base_m + 0] = (real >> 8) & 0xFF;
//    spi_rx_test[base_m + 1] = (real     ) & 0xFF;
//    spi_rx_test[base_m + 2] = ((-imag) >> 8) & 0xFF;
//    spi_rx_test[base_m + 3] = ((-imag)     ) & 0xFF;
//}

//// ================================================================
//// Phase quantizer (UNCHANGED AS YOU REQUESTED)
//// ================================================================
//void fft_postprocess_phase_quantize(const uint8_t *spi_rx, float32_t *X_full)
//{
//    const float32_t phase_step = 2.0f * PI_F / NUM_PHASE_LEVELS;

//    for (int i = 0; i < 2 * FFT_N; i++)
//        X_full[i] = 0.0f;

//    int16_t r0 = (int16_t)(((uint16_t)spi_rx[0] << 8) | spi_rx[1]);
//    X_full[0] = (float32_t)r0 * AUDIO_SCALE;
//    X_full[1] = 0.0f;

//    for (int k = 1; k < HALF_BINS - 1; k++)
//    {
//        uint16_t base = 4 * k;

//        int16_t real16 =
//            (int16_t)(((uint16_t)spi_rx[base+0] << 8) | spi_rx[base+1]);
//        int16_t imag16 =
//            (int16_t)(((uint16_t)spi_rx[base+2] << 8) | spi_rx[base+3]);

//        float32_t Re = real16 * AUDIO_SCALE;
//        float32_t Im = imag16 * AUDIO_SCALE;

//        float32_t mag = sqrtf(Re*Re + Im*Im);
//        float32_t phi = atan2f(Im, Re);

//        float32_t phi_q = phase_step * roundf(phi / phase_step);
//        float32_t sin_phi, cos_phi;
//        arm_sin_cos_f32(phi_q, &sin_phi, &cos_phi);

//        X_full[2*k]     = mag * cos_phi;
//        X_full[2*k + 1] = mag * sin_phi;
//    }

//    int k = HALF_BINS - 1;
//    uint16_t base = 4 * k;

//    int16_t real16 =
//        (int16_t)(((uint16_t)spi_rx[base+0] << 8) | spi_rx[base+1]);
//    X_full[2*k] = real16 * AUDIO_SCALE;
//    X_full[2*k + 1] = 0.0f;

//    X_full[2 * HALF_BINS]     = 0.0f;
//    X_full[2 * HALF_BINS + 1] = 0.0f;

//    for (int k2 = 1; k2 < HALF_BINS; k2++)
//    {
//        int km = FFT_N - k2;
//        X_full[2*km]     =  X_full[2*k2];
//        X_full[2*km + 1] = -X_full[2*k2 + 1];
//    }
//}

//// ================================================================
//// IFFT 512 (UNCHANGED)
//// ================================================================
//void runInverseFFT512_fromSpectrum(float32_t *buf)
//{
//    const arm_cfft_instance_f32 *cfft = &arm_cfft_sR_f32_len512;
//    arm_cfft_f32(cfft, buf, 1, 1);
//    arm_scale_f32(buf, 1.0f / FFT_N, buf, 2 * FFT_N);
//}

//// ================================================================
//// Overlap-add → audio ring buffer (UNCHANGED)
//// ================================================================
//void process_frame_and_push(float32_t *ifft_buf)
//{
//    for (int n = 0; n < FFT_N; n++)
//    {
//        // Extract real + imag
//        float32_t Re = ifft_buf[2*n];
//        float32_t Im = ifft_buf[2*n + 1];

//        // NEW: Use IFFT magnitude (Option B)
//        float32_t s = sqrtf(Re*Re + Im*Im);

//        // Apply Hann window
//        s *= hann_win[n];

//        // OLA accumulation
//        uint32_t idx = (ola_write_pos + n) % BUFFER_SIZE;
//        ola_buffer[idx] += s;

//        // Safety clamps
//        if (ola_buffer[idx] > 5.0f)  ola_buffer[idx] = 5.0f;
//        if (ola_buffer[idx] < -5.0f) ola_buffer[idx] = -5.0f;

//        // Write into ISR audio buffer
//        audio_push(ola_buffer[idx]);
//    }

//    // Advance OLA pointer
//    ola_write_pos = (ola_write_pos + HOP) % BUFFER_SIZE;
//}

//void process_frame_and_push(float32_t *ifft_buf)
//{
//    for (int n = 0; n < FFT_N; n++)
//    {
//        float32_t s = ifft_buf[2*n] * hann_win[n];

//        uint32_t idx = (ola_write_pos + n) % BUFFER_SIZE;
//        ola_buffer[idx] += s;

//        if (ola_buffer[idx] > 5.0f)   ola_buffer[idx] = 5.0f;
//        if (ola_buffer[idx] < -5.0f)  ola_buffer[idx] = -5.0f;

//        audio_push(ola_buffer[idx]);
//    }

//    ola_write_pos = (ola_write_pos + HOP) % BUFFER_SIZE;
//}

// ================================================================
// MAIN
// ================================================================
//int main(void)
//{
//    configureFlash();
//    configureClock();
//    gpioEnable(GPIO_PORT_A);
//    gpioEnable(GPIO_PORT_B);
//    gpioEnable(GPIO_PORT_C);

//    RCC->APB2ENR |= RCC_APB2ENR_TIM15EN;
//    initTIM(TIM15);

//    printf("\n===== AUDIO + IFFT PIPELINE START =====\n");

//    generate_sine_table();
//    configureDAC();

//    memset(audio_buffer, 0, sizeof(audio_buffer));
//    memset(ola_buffer,   0, sizeof(ola_buffer));

//    audio_r = audio_w = 0;

//    initHann();

//    // ----------------------------------------------------
//    // FIRST FRAME MUST BE GENERATED BEFORE ENABLING TIM2
//    // ----------------------------------------------------
//    fill_fake_fft_frame_sine(500.0f);
//    fft_postprocess_phase_quantize(spi_rx_test, X_full_test);
//    runInverseFFT512_fromSpectrum(X_full_test);
//    process_frame_and_push(X_full_test);

//    initTIM2_16kHz();
//    __enable_irq();

//    printf("Streaming FFT/IFFT reconstructed audio...\n");

//    while (1)
//    {
//        // SPI-safe DAC write
//        if (dac_update_flag)
//        {
//            // printf("dac update\n");
//            setDAC(sample_to_dac);
//            dac_update_flag = 0;
//        }

//        // DSP pipeline
//        fill_fake_fft_frame_sine(500.0f);
//        // printf("fill\n");
//        fft_postprocess_phase_quantize(spi_rx_test, X_full_test);
//        // printf("phase\n");
//        runInverseFFT512_fromSpectrum(X_full_test);
//        // printf("inverse\n");
//        process_frame_and_push(X_full_test);
//        // printf("frame push\n");
//    }
//}





// ================================================================
// Combined Audio Output + FFT/IFFT + Phase Quantization Pipeline
// STM32L432KC — TIM2 ISR for DAC output
// ================================================================

//#include "arm_math.h"
//#include "arm_const_structs.h"
//#include "main.h"
//#include <math.h>
//#include <stdint.h>
//#include <stdio.h>
//#include <string.h>

//// =============================
//// Audio Config
//// =============================
//#define SAMPLE_RATE     16000.0f
//#define HOP_SIZE        128
//#define FRAME_SIZE      512

//// IMPORTANT: reduce buffer size to fit RAM
//#define BUFFER_SIZE     4096   // FIX: reduced from 8192 → 4096

//#define PI_F            3.14159265358979f

//// =============================
//// DAC Mapping
//// =============================
//#define V_MID   2.5f
//#define V_AMP   1.0f
//#define V_MIN   0.0f
//#define V_MAX   5.0f

//// =============================
//// Audio buffer shared with ISR
//// =============================
//static float32_t audio_buffer[BUFFER_SIZE];
//static volatile uint32_t audio_r = 0;
//static volatile uint32_t audio_w = 0;

//// =============================
//// Sine table (your original)
//// =============================
//#define SINE_TABLE_SIZE 512
//static float32_t sine_table[SINE_TABLE_SIZE];

//// Rename to avoid collision with FFT Hann window
//static float32_t hann_win_audio[FRAME_SIZE];

//// ================================================================
//// ▼ PATCH — FFT/IFFT integration buffers
//// ================================================================
//#define FFT_N             512
//#define HALF_BINS         (FFT_N / 2)
//#define NUM_PHASE_LEVELS  16
//#define AUDIO_SCALE       (1.0f / 32768.0f)
//#define HOP               (FFT_N / 4)

//static uint8_t    spi_rx_test[1024];
//static float32_t  X_full_test[2 * FFT_N];

//static float32_t  hann_win[FFT_N];          // FFT Hann window
//static float32_t  ola_buffer[BUFFER_SIZE];  // OLA accumulation buffer
//static uint32_t   ola_write_pos = 0;

//// ================================================================
//// Function Prototypes
//// ================================================================
//void initTIM2_16kHz(void);
//void generate_sine_table(void);

//// ======================================
//// Generate a 500 Hz sine wave table
//// ======================================
//void generate_sine_table(void)
//{
//    for (int n = 0; n < SINE_TABLE_SIZE; n++)
//    {
//        float phase = 2.0f * PI_F * n / SINE_TABLE_SIZE;
//        sine_table[n] = sinf(phase);
//    }

//    printf("Sine table created: [%.3f, %.3f, %.3f...]\n",
//        sine_table[0], sine_table[1], sine_table[2]);
//}

//// ======================================
//// Timer 2 @ 16 kHz
//// ======================================
//void initTIM2_16kHz(void)
//{
//    RCC->APB1ENR1 |= RCC_APB1ENR1_TIM2EN;

//    TIM2->PSC = 8;
//    TIM2->ARR = 999;

//    TIM2->CNT = 0;
//    TIM2->DIER |= TIM_DIER_UIE;
//    NVIC->ISER[0] |= (1 << TIM2_IRQn);
//    TIM2->CR1 |= TIM_CR1_CEN;
//}

//// ======================================
//// TIMER 2 ISR: runs at 16 kHz
//// ======================================
//void TIM2_IRQHandler(void)
//{
//    if (TIM2->SR & TIM_SR_UIF)
//    {
//        TIM2->SR &= ~TIM_SR_UIF;

//        float32_t s = audio_buffer[audio_r];
//        audio_r = (audio_r + 1) % BUFFER_SIZE;
//        // printf("dacCode value %f\n", s);

//        float32_t v = V_MID + V_AMP * s;

//        if (v < V_MIN) v = V_MIN;
//        if (v > V_MAX) v = V_MAX;

//        printf("dacCode value %f\n", v);

//        setDAC(v);
//    }
//}

//// ======================================
//// Push one sample into audio buffer
//// ======================================
//static inline void audio_push(float32_t s)
//{
//    audio_buffer[audio_w] = s;
//    audio_w = (audio_w + 1) % BUFFER_SIZE;
//}

//// ================================================================
//// ▼ PATCH — FFT Hann init
//// ================================================================
//void initHann(void)
//{
//    for (int n = 0; n < FFT_N; n++)
//    {
//        hann_win[n] =
//            0.5f - 0.5f * arm_cos_f32(2.0f * PI_F * n / (FFT_N - 1));
//    }
//}

//// ================================================================
//// ▼ PATCH — fake FFT sinewave generator
//// ================================================================
//void fill_fake_fft_frame_sine(float freq_hz)
//{
//    memset(spi_rx_test, 0, sizeof(spi_rx_test));

//    int k = (int)((freq_hz * FFT_N) / SAMPLE_RATE);

//    float A = 30000.0f;  // amplitude

//    // Positive
//    spi_rx_test[4*k + 0] = (int16_t)(A/2) >> 8;
//    spi_rx_test[4*k + 1] = (int16_t)(A/2);

//    // Negative
//    int km = FFT_N - k;
//    spi_rx_test[4*km + 0] = (int16_t)(A/2) >> 8;
//    spi_rx_test[4*km + 1] = (int16_t)(A/2);
//}

////void fill_fake_fft_frame_sine(float freq_hz)
////{
////    memset(spi_rx_test, 0, sizeof(spi_rx_test));

////    int k = (int)((freq_hz * FFT_N) / SAMPLE_RATE);

////    if (k <= 0 || k >= FFT_N/2)
////        return;

////    int16_t real = 16000;
////    int16_t imag = 0;

////    uint16_t base = 4 * k;
////    spi_rx_test[base + 0] = (real >> 8) & 0xFF;
////    spi_rx_test[base + 1] = (real     ) & 0xFF;
////    spi_rx_test[base + 2] = (imag >> 8) & 0xFF;
////    spi_rx_test[base + 3] = (imag     ) & 0xFF;

////    int k_mirror = FFT_N - k;
////    uint16_t base_m = 4 * k_mirror;

////    spi_rx_test[base_m + 0] = (real >> 8) & 0xFF;
////    spi_rx_test[base_m + 1] = (real     ) & 0xFF;
////    spi_rx_test[base_m + 2] = ((-imag) >> 8) & 0xFF;
////    spi_rx_test[base_m + 3] = ((-imag)     ) & 0xFF;
////}

//// ================================================================
//// ▼ PATCH — phase quantizer
//// ================================================================
//void fft_postprocess_phase_quantize(const uint8_t *spi_rx, float32_t *X_full)
//{
//    const float32_t phase_step = 2.0f * PI_F / NUM_PHASE_LEVELS;

//    for (int i = 0; i < 2 * FFT_N; i++)
//        X_full[i] = 0.0f;

//    int16_t r0 = (int16_t)(((uint16_t)spi_rx[0] << 8) | spi_rx[1]);
//    X_full[0] = (float32_t)r0 * AUDIO_SCALE;
//    X_full[1] = 0.0f;

//    for (int k = 1; k < HALF_BINS - 1; k++) {

//        uint16_t base = 4 * k;

//        int16_t real16 =
//            (int16_t)(((uint16_t)spi_rx[base+0] << 8) | spi_rx[base+1]);
//        int16_t imag16 =
//            (int16_t)(((uint16_t)spi_rx[base+2] << 8) | spi_rx[base+3]);

//        float32_t Re = real16 * AUDIO_SCALE;
//        float32_t Im = imag16 * AUDIO_SCALE;

//        float32_t mag = sqrtf(Re*Re + Im*Im);
//        float32_t phi = atan2f(Im, Re);

//        float32_t phi_q = phase_step * roundf(phi / phase_step);
//        float32_t sin_phi, cos_phi;
//        arm_sin_cos_f32(phi_q, &sin_phi, &cos_phi);

//        X_full[2*k]     = mag * cos_phi;
//        X_full[2*k + 1] = mag * sin_phi;
//    }

//    int k = HALF_BINS - 1;
//    uint16_t base = 4 * k;

//    int16_t real16 = (int16_t)(((uint16_t)spi_rx[base+0] << 8) |
//                                spi_rx[base+1]);
//    X_full[2*k] = real16 * AUDIO_SCALE;
//    X_full[2*k + 1] = 0.0f;

//    X_full[2 * HALF_BINS]     = 0.0f;
//    X_full[2 * HALF_BINS + 1] = 0.0f;

//    for (int k2 = 1; k2 < HALF_BINS; k2++)
//    {
//        int km = FFT_N - k2;
//        X_full[2*km]     =  X_full[2*k2];
//        X_full[2*km + 1] = -X_full[2*k2 + 1];
//    }
//}

//// ================================================================
//// ▼ PATCH — IFFT
//// ================================================================
//void runInverseFFT512_fromSpectrum(float32_t *buf)
//{
//    const arm_cfft_instance_f32 *cfft = &arm_cfft_sR_f32_len512;
//    arm_cfft_f32(cfft, buf, 1, 1);
//    arm_scale_f32(buf, 1.0f / FFT_N, buf, 2 * FFT_N);
//}

//// ================================================================
//// ▼ PATCH — OLA accumulate + push
//// ================================================================
//void process_frame_and_push(float32_t *ifft_buf)
//{
//    for (int n = 0; n < FFT_N; n++)
//    {
//        float32_t s = ifft_buf[2*n] * hann_win[n];

//        uint32_t idx = (ola_write_pos + n) % BUFFER_SIZE;

//        // TRUE OLA accumulation
//        ola_buffer[idx] += s;

//        // Protect against runaway accumulation
//        if (ola_buffer[idx] > 5.0f)   ola_buffer[idx] = 5.0f;
//        if (ola_buffer[idx] < -5.0f)  ola_buffer[idx] = -5.0f;

//        audio_push(ola_buffer[idx]);
//    }

//    ola_write_pos = (ola_write_pos + HOP) % BUFFER_SIZE;
//}

//// ======================================
//// MAIN
//// ======================================
//int main(void)
//{
//    configureFlash();
//    configureClock();
//    gpioEnable(GPIO_PORT_A);
//    gpioEnable(GPIO_PORT_B);
//    gpioEnable(GPIO_PORT_C);

//    RCC->APB1ENR1 |= RCC_APB1ENR1_TIM2EN;
//    RCC->APB2ENR |= RCC_APB2ENR_TIM15EN;
//    initTIM(TIM15);

//    printf("\n===== AUDIO + IFFT PIPELINE START =====\n");

//    generate_sine_table();  // original, but unused now
//    configureDAC();

//    // FIX: remove sine prefill — instead clear buffer cleanly
//    memset(audio_buffer, 0, sizeof(audio_buffer));
//    audio_r = 0;
//    audio_w = 0;

//    memset(ola_buffer, 0, sizeof(ola_buffer));
//    initHann();

//    // ------------------------------------------------------
//    // IMPORTANT FIX:
//    // Produce first frame BEFORE enabling the 16 kHz ISR
//    // ------------------------------------------------------
//    fill_fake_fft_frame_sine(500.0f);
//    fft_postprocess_phase_quantize(spi_rx_test, X_full_test);
//    runInverseFFT512_fromSpectrum(X_full_test);
//    process_frame_and_push(X_full_test);

//    // Now start interrupt-driven DAC output
//    initTIM2_16kHz();
//    __enable_irq();

//    printf("Streaming FFT/IFFT reconstructed audio...\n");

//    while (1)
//    {
//        // Produce continuous sine wave through FFT → IFFT
//        fill_fake_fft_frame_sine(500.0f);
//        // printf("fill\n");
//        fft_postprocess_phase_quantize(spi_rx_test, X_full_test);
//        // printf("phase\n");
//        runInverseFFT512_fromSpectrum(X_full_test);
//        // printf("inverse\n");
//        process_frame_and_push(X_full_test);
//        // printf("psuh\n");
//    }
//}



//// ================================================================
//// Combined Audio Output + FFT/IFFT + Phase Quantization Pipeline
//// STM32L432KC — TIM2 ISR for DAC output
//// ================================================================

//#include "arm_math.h"
//#include "arm_const_structs.h"
//#include "main.h"
//#include <math.h>
//#include <stdint.h>
//#include <stdio.h>
//#include <string.h>

//// =============================
//// Audio Config
//// =============================
//#define SAMPLE_RATE     16000.0f
//#define HOP_SIZE        128
//#define FRAME_SIZE      512
//#define BUFFER_SIZE     4096

//#define PI_F            3.14159265358979f

//// =============================
//// DAC Mapping
//// =============================
//#define V_MID   2.5f
//#define V_AMP   1.0f
//#define V_MIN   0.0f
//#define V_MAX   5.0f

//// =============================
//// Audio buffer shared with ISR
//// =============================
//static float32_t audio_buffer[BUFFER_SIZE];
//static volatile uint32_t audio_r = 0;
//static volatile uint32_t audio_w = 0;

//// =============================
//// Sine table (test mode)
//// =============================
//#define SINE_TABLE_SIZE 512
//static float32_t sine_table[SINE_TABLE_SIZE];

//// NOTE: ORIGINAL NAME CHANGED TO AVOID COLLISION WITH FFT HANN WINDOW
//static float32_t hann_win_audio[FRAME_SIZE];

//// ================================================================
//// ▼ PATCH SECTION — FFT/IFFT INTEGRATION BUFFERS
//// ================================================================
////// >>> PATCH BEGIN — FFT/iFFT integration
//#define FFT_N             512
//#define HALF_BINS         (FFT_N / 2)
//#define NUM_PHASE_LEVELS  16
//#define AUDIO_SCALE       (1.0f / 32768.0f)
//#define HOP               (FFT_N / 4)

//static uint8_t    spi_rx_test[1024];
//static float32_t  X_full_test[2 * FFT_N];

//static float32_t  hann_win[FFT_N];          // FFT Hann window
//static float32_t  ola_buffer[BUFFER_SIZE];  // Use main buffer size
//static uint32_t   ola_write_pos = 0;
////// >>> PATCH END
//// ================================================================

//// =============================
//// Function Prototypes
//// =============================
//void initTIM2_16kHz(void);
//void generate_sine_table(void);

//// ======================================
//// Generate a 500 Hz sine wave table
//// ======================================
//void generate_sine_table(void)
//{
//    for (int n = 0; n < SINE_TABLE_SIZE; n++)
//    {
//        float phase = 2.0f * PI_F * n / SINE_TABLE_SIZE;
//        sine_table[n] = sinf(phase);
//    }

//    printf("Sine table created: [%.3f, %.3f, %.3f...]\n",
//        sine_table[0], sine_table[1], sine_table[2]);
//}

//// ======================================
//// Timer 2 @ 16 kHz
//// ======================================
//void initTIM2_16kHz(void)
//{
//    RCC->APB1ENR1 |= RCC_APB1ENR1_TIM2EN;

//    TIM2->PSC = 1;
//    TIM2->ARR = 999;

//    TIM2->CNT = 0;
//    TIM2->DIER |= TIM_DIER_UIE;
//    NVIC->ISER[0] |= (1 << TIM2_IRQn);
//    TIM2->CR1 |= TIM_CR1_CEN;
//}

//// ======================================
//// TIMER 2 ISR: runs at 16 kHz
//// ======================================
//void TIM2_IRQHandler(void)
//{
//    if (TIM2->SR & TIM_SR_UIF)
//    {
//        TIM2->SR &= ~TIM_SR_UIF;

//        float32_t s = audio_buffer[audio_r];
//        audio_r = (audio_r + 1) % BUFFER_SIZE;

//        float32_t v = V_MID + V_AMP * s;

//        if (v < V_MIN) v = V_MIN;
//        if (v > V_MAX) v = V_MAX;

//        setDAC(v);
//    }
//}

//// ======================================
//// Push one sample into audio buffer
//// ======================================
//static inline void audio_push(float32_t s)
//{
//    audio_buffer[audio_w] = s;
//    audio_w = (audio_w + 1) % BUFFER_SIZE;
//}

//// ================================================================
//// ▼ PATCH SECTION — Hann Window for FFT
//// ================================================================
////// >>> PATCH BEGIN — Hann init

//void initHann(void)
//{
//    for (int n = 0; n < FFT_N; n++)
//    {
//        hann_win[n] = 0.5f - 0.5f * arm_cos_f32(2.0f * PI_F * n / (FFT_N - 1));
//    }
//}
////// >>> PATCH END
//// ================================================================

//// ================================================================
//// ▼ PATCH SECTION — Phase Quantization
//// ================================================================
////// >>> PATCH BEGIN — Phase quantizer
//void fft_postprocess_phase_quantize(const uint8_t *spi_rx, float32_t *X_full)
//{
//    const float32_t phase_step = 2.0f * PI_F / NUM_PHASE_LEVELS;

//    for (int i = 0; i < 2 * FFT_N; i++) 
//        X_full[i] = 0.0f;

//    int16_t r0 = (int16_t)(((uint16_t)spi_rx[0] << 8) | spi_rx[1]);
//    X_full[0] = (float32_t)r0 * AUDIO_SCALE;
//    X_full[1] = 0.0f;

//    for (int k = 1; k < HALF_BINS - 1; k++) {

//        uint16_t base = 4 * k;

//        int16_t real16 = (int16_t)(((uint16_t)spi_rx[base + 0] << 8) | spi_rx[base + 1]);
//        int16_t imag16 = (int16_t)(((uint16_t)spi_rx[base + 2] << 8) | spi_rx[base + 3]);

//        float32_t Re = (float32_t)real16 * AUDIO_SCALE;
//        float32_t Im = (float32_t)imag16 * AUDIO_SCALE;

//        float32_t mag = sqrtf(Re*Re + Im*Im);
//        float32_t phi = atan2f(Im, Re);

//        float32_t phi_q = phase_step * roundf(phi / phase_step);
//        float32_t sin_phi, cos_phi;

//        arm_sin_cos_f32(phi_q, &sin_phi, &cos_phi);

//        X_full[2*k]     = mag * cos_phi;
//        X_full[2*k + 1] = mag * sin_phi;
//    }

//    int k = HALF_BINS - 1;
//    uint16_t base = 4 * k;
//    int16_t real16 = (int16_t)(((uint16_t)spi_rx[base + 0] << 8) | spi_rx[base + 1]);
//    X_full[2*k]     = (float32_t)real16 * AUDIO_SCALE;
//    X_full[2*k + 1] = 0.0f;

//    X_full[2 * HALF_BINS]     = 0.0f;
//    X_full[2 * HALF_BINS + 1] = 0.0f;

//    for (int k2 = 1; k2 < HALF_BINS; k2++) {
//        int k_mirror = FFT_N - k2;
//        X_full[2*k_mirror]     =  X_full[2*k2];
//        X_full[2*k_mirror + 1] = -X_full[2*k2 + 1];
//    }
//}
////// >>> PATCH END
//// ================================================================

//// ================================================================
//// ▼ PATCH SECTION — IFFT 512
//// ================================================================
////// >>> PATCH BEGIN — IFFT wrapper
//void runInverseFFT512_fromSpectrum(float32_t *buf)
//{
//    const arm_cfft_instance_f32 *cfft = &arm_cfft_sR_f32_len512;
//    arm_cfft_f32(cfft, buf, 1, 1);
//    arm_scale_f32(buf, 1.0f / FFT_N, buf, 2 * FFT_N);
//}
////// >>> PATCH END
//// ================================================================

//// ================================================================
//// ▼ PATCH SECTION — OLA → audio buffer (Option A: true OLA)
//// ================================================================
////// >>> PATCH BEGIN — OLA accumulate + push
//void process_frame_and_push(float32_t *ifft_buf)
//{
//    for (int n = 0; n < FFT_N; n++)
//    {
//        float32_t s = ifft_buf[2*n];
//        s *= hann_win[n];

//        uint32_t idx = (ola_write_pos + n) % BUFFER_SIZE;

//        // accumulate overlap-add
//        ola_buffer[idx] += s;

//        // push to ISR output buffer
//        audio_push(ola_buffer[idx]);

//        // NOTE: no clearing; true OLA accumulation
//    }

//    ola_write_pos = (ola_write_pos + HOP) % BUFFER_SIZE;
//}
////// >>> PATCH END
//// ================================================================
////// NEW: create a fake FFT frame that produces a pure sine wave
//void fill_fake_fft_frame_sine(float freq_hz)
//{
//    memset(spi_rx_test, 0, sizeof(spi_rx_test));

//    // FFT bin index
//    int k = (int)((freq_hz * FFT_N) / SAMPLE_RATE);

//    // Amplitude in 16-bit format (scaled)
//    int16_t real = 15000;  // magnitude
//    int16_t imag = 0;

//    // Positive-frequency bin +k
//    uint16_t base = 4 * k;
//    spi_rx_test[base + 0] = (real >> 8) & 0xFF;
//    spi_rx_test[base + 1] = (real     ) & 0xFF;
//    spi_rx_test[base + 2] = (imag >> 8) & 0xFF;
//    spi_rx_test[base + 3] = (imag     ) & 0xFF;

//    // Negative-frequency conjugate bin (mirror)
//    int k_mirror = FFT_N - k;
//    uint16_t base_m = 4 * k_mirror;

//    spi_rx_test[base_m + 0] = (real >> 8) & 0xFF;
//    spi_rx_test[base_m + 1] = (real     ) & 0xFF;
//    spi_rx_test[base_m + 2] = (-(imag) >> 8) & 0xFF;
//    spi_rx_test[base_m + 3] = (-(imag)     ) & 0xFF;
//}


//// ======================================
//// MAIN
//// ======================================
//int main(void)
//{
//    configureFlash();
//    configureClock();
//    gpioEnable(GPIO_PORT_A);
//    gpioEnable(GPIO_PORT_B);
//    gpioEnable(GPIO_PORT_C);

//    // RCC->APB1ENR1 |= RCC_APB1ENR1_TIM2EN;
//    RCC->APB2ENR |= RCC_APB2ENR_TIM15EN;
//    initTIM(TIM15);

//    printf("\n===== AUDIO + IFFT PIPELINE START =====\n");

//    generate_sine_table();
//    configureDAC();

//    printf("Pre-filling audio buffer...\n");

//    printf("Streaming FFT/IFFT reconstructed audio...\n");
//    memset(audio_buffer, 0, sizeof(audio_buffer));
//    audio_w = 0;
//    audio_r = 0;

//    // laast 
//    initHann();

//    // Start 16 kHz timer interrupt


//    while (1)
//    {
//        // 1) Create fake FFT input frame
//        fill_fake_fft_frame_sine(500.0f);  // generate 500 Hz sine wave

//        // 2) Phase quantize
//        fft_postprocess_phase_quantize(spi_rx_test, X_full_test);

//        // 3) IFFT
//        runInverseFFT512_fromSpectrum(X_full_test);

//        // 4) OLA + push to audio ring
//        process_frame_and_push(X_full_test);
//    }
//}




//// tim2_sine_output.c
//// Timer 2 interrupt at 16 kHz → output a 500 Hz sine wave via setDAC()
//// Based on your verified working Timer2 ISR code

//// ================================================================
//// 16 kHz Audio Output Pipeline + FFT/iFFT Integration
//// STM32L432KC — TIM2 ISR for DAC output
//// ================================================================

//#include "arm_math.h"
//#include "arm_const_structs.h"
//#include "main.h"
//#include <math.h>
//#include <stdint.h>
//#include <stdio.h>
//#include <string.h>

//// =============================
//// Audio Config
//// =============================
//#define SAMPLE_RATE     16000.0f
//#define HOP_SIZE        128             // you already use this
//#define FRAME_SIZE      512
//#define BUFFER_SIZE     8192            // audio circular buffer

//#define PI_F            3.14159265358979f

//// =============================
//// DAC Mapping
//// =============================
//#define V_MID   2.5f
//#define V_AMP   1.0f
//#define V_MIN   0.0f
//#define V_MAX   5.0f

//// =============================
//// Audio buffer shared with ISR
//// =============================
//static float32_t audio_buffer[BUFFER_SIZE];
//static volatile uint32_t audio_r = 0;   // ISR reads
//static volatile uint32_t audio_w = 0;   // main writes

//// =============================
//// Sine table (test mode)
//// =============================
//#define SINE_TABLE_SIZE 512
//static float32_t sine_table[SINE_TABLE_SIZE];

//// =============================
//// Function Prototypes
//// =============================
//void initTIM2_16kHz(void);
//void generate_sine_table(void);

//// =============================
//// FFT/iFFT Buffers
//// =============================
//static float32_t X_full[2 * FRAME_SIZE];
//static float32_t hann_win[FRAME_SIZE];

//// ======================================
//// Generate a 500 Hz sine wave table
//// ======================================
//void generate_sine_table(void)
//{
//    for (int n = 0; n < SINE_TABLE_SIZE; n++)
//    {
//        float phase = 2.0f * PI_F * n / SINE_TABLE_SIZE;
//        sine_table[n] = sinf(phase);
//    }

//    printf("Sine table created: [%.3f, %.3f, %.3f...]\n",
//        sine_table[0], sine_table[1], sine_table[2]);
//}

//// ======================================
//// Timer 2 @ 16 kHz
//// ======================================
//void initTIM2_16kHz(void)
//{
//    // Enable clock
//    RCC->APB1ENR1 |= RCC_APB1ENR1_TIM2EN;

//    // For 16kHz update:
//    // 80 MHz / (PSC+1) / (ARR+1) = 16000
//    //
//    // Your working setting:
//    TIM2->PSC = 8;        // 80MHz / 2 = 40 MHz
//    TIM2->ARR = 999;     // 40 MHz / 2500 = 16 kHz

//    TIM2->CNT = 0;
//    TIM2->DIER |= TIM_DIER_UIE;

//    // Enable interrupt EXACTLY like your EXTI example
//    NVIC->ISER[0] |= (1 << TIM2_IRQn);

//    TIM2->CR1 |= TIM_CR1_CEN;
//}

//// ======================================
//// TIMER 2 ISR: runs at 16 kHz
//// Reads from circular buffer → DAC
//// ======================================
//void TIM2_IRQHandler(void)
//{
//    if (TIM2->SR & TIM_SR_UIF)
//    {
//        TIM2->SR &= ~TIM_SR_UIF;

//        // Read next audio sample
//        float32_t s = audio_buffer[audio_r];
//        audio_r = (audio_r + 1) % BUFFER_SIZE;

//        // Map from [-1,+1] → [0,5V]
//        float32_t v = V_MID + V_AMP * s;

//        if (v < V_MIN) v = V_MIN;
//        if (v > V_MAX) v = V_MAX;

//        setDAC(v);
//    }
//}

//// ======================================
//// Push one sample into audio buffer
//// (main loop writes here)
//// ======================================

//static inline void audio_push(float32_t s)
//{
//    audio_buffer[audio_w] = s;
//    audio_w = (audio_w + 1) % BUFFER_SIZE;
//}

//// ======================================
//// MAIN
//// ======================================
//int main(void)
//{
//    configureFlash();
//    configureClock();
//    gpioEnable(GPIO_PORT_A);
//    gpioEnable(GPIO_PORT_B);
//    gpioEnable(GPIO_PORT_C);

//    RCC->APB1ENR1 |= RCC_APB1ENR1_TIM2EN;
//    RCC->APB2ENR |= RCC_APB2ENR_TIM15EN;  // for delay_millis
//    initTIM(TIM15);                       // your known-good delay timer

//    printf("\n===== AUDIO + IFFT PIPELINE START =====\n");
//    printf("Sample rate: %.2f Hz\n", SAMPLE_RATE);

//    // ---------------------------
//    // 1. Generate sine test
//    // ---------------------------
//    generate_sine_table();

//    // Adding stuff 
//    configureDAC();

//    // ADDIITON 
//    printf("Pre-filling audio buffer...\n");
//    for (int i = 0; i < BUFFER_SIZE; i++)
//    {
//    audio_buffer[i] = sine_table[i % SINE_TABLE_SIZE];
//    }
//    audio_w = BUFFER_SIZE;
//    audio_r = 0;

//    // ---------------------------
//    // 2. Start audio ISR
//    // ---------------------------
//    initTIM2_16kHz();
//    printf("TIM2 ISR running at 16 kHz.\n");

//    __enable_irq();

//    // Debug: produce 500 Hz sine
//    uint32_t idx = 0;

//    printf("Streaming 500 Hz test tone...\n");


//    while (1)
//    {
//        static float phase = 0.0f;
//        static const float phase_step = (500.0f * SINE_TABLE_SIZE) / SAMPLE_RATE;
//        for (int i = 0; i < 256; i++)
//        {
//          float32_t s = sine_table[(uint32_t)phase & (SINE_TABLE_SIZE - 1)];
//          phase += phase_step;
//          if (phase >= SINE_TABLE_SIZE)
//          phase -= SINE_TABLE_SIZE;
//          audio_push(s);
//        }


//        // delay_millis(TIM15, 10);
//        // printf("Buffered more samples...\n");
//    }
//}

//#include <stdio.h>
//#include <math.h>
//#include "main.h"
//#include "arm_math.h"
//#include "arm_const_structs.h"

//#define SAMPLE_RATE     16000.0f   // Hz
//#define SINE_FREQ       500.0f     // Hz
//#define TABLE_SIZE      512        // Must be power of 2
//#define PI_F            3.14159265358979f

//// DAC output mapping
//#define V_MIN           0.0f
//#define V_MAX           5.0f
//#define V_MID           2.5f       // center (DAC mid rail)
//#define V_AMP           1.0f       // 1 V peak sine

//static float32_t sine_table[TABLE_SIZE];
//static volatile uint32_t table_idx = 0;
//volatile uint32_t tim2_count = 0;

//// Forward declarations
//void initTIM2_16kHz(void);
//void generate_sine_table(void);

//int main(void)
//{
//    configureFlash();
//    configureClock();
//    gpioEnable(GPIO_PORT_A);
//    gpioEnable(GPIO_PORT_B);
//    gpioEnable(GPIO_PORT_C);

//    // =================================
//    // Enable TIM2 clock
//    // =================================
//    RCC->APB1ENR1 |= RCC_APB1ENR1_TIM2EN;

//    // Build sine table
//    generate_sine_table();
//    RCC->APB2ENR |= (RCC_APB2ENR_TIM15EN);
//    initTIM(TIM15);

//    // Init DAC (your function)
//    configureDAC();

//    // Start 16 kHz ISR
//    initTIM2_16kHz();

//    // Enable global interrupts
//    __enable_irq();

//    printf("===== Timer2 16 kHz Sine Output Test =====\n");

//    while(1)
//    {
//        delay_millis(TIM15, 1000);
//        printf("Main alive... ISR count = %lu\n", tim2_count);
//    }
//}


//// ============================================================
//// Generate 500 Hz sine lookup table
//// ============================================================
//void generate_sine_table(void)
//{
//    for (int n = 0; n < TABLE_SIZE; n++)
//    {
//        float phase = 2.0f * PI_F * n / TABLE_SIZE;
//        sine_table[n] = sinf(phase);
//    }

//    printf("Sine table created: [%.3f, %.3f, %.3f...]\n",
//           sine_table[0], sine_table[1], sine_table[2]);
//}


//// ============================================================
//// Configure TIM2 for 16 kHz interrupts
//// ============================================================
//void initTIM2_16kHz(void)
//{
//    TIM2->PSC = 1;       // 80MHz / (4+1) = 16 MHz
//    TIM2->ARR = 999;     // 16MHz / (999+1) = 16000 Hz
//    TIM2->CNT = 0;

//    TIM2->DIER |= TIM_DIER_UIE;   // Enable update interrupt

//    // EXACT NVIC enable method verified earlier
//    NVIC->ISER[0] |= (1 << TIM2_IRQn);

//    TIM2->CR1 |= TIM_CR1_CEN;     // Start timer
//}


//// ============================================================
//// TIMER 2 INTERRUPT — 16 kHz audio sample generator
//// ============================================================
//static float phase = 0.0f;
//static float phase_step = (500.0f / SAMPLE_RATE) * TABLE_SIZE;

//void TIM2_IRQHandler(void)
//{
//    if (TIM2->SR & TIM_SR_UIF)
//    {
//        TIM2->SR &= ~TIM_SR_UIF;

//        int idx = (int)phase & (TABLE_SIZE - 1);
//        float s = sine_table[idx];

//        phase += phase_step;
//        if (phase >= TABLE_SIZE)
//            phase -= TABLE_SIZE;

//        setDAC(2.5f + 1.0f * s);
//    }
//}