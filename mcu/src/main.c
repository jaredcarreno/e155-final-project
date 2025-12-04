// tim2_sine_output.c
// Timer 2 interrupt at 16 kHz → output a 500 Hz sine wave via setDAC()
// Based on your verified working Timer2 ISR code

// ================================================================
// 16 kHz Audio Output Pipeline + FFT/iFFT Integration
// STM32L432KC — TIM2 ISR for DAC output
// ================================================================

#include "arm_math.h"
#include "arm_const_structs.h"
#include "main.h"
#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

// =============================
// Audio Config
// =============================
#define SAMPLE_RATE     16000.0f
#define HOP_SIZE        128             // you already use this
#define FRAME_SIZE      512
#define BUFFER_SIZE     8192            // audio circular buffer

#define PI_F            3.14159265358979f

// =============================
// DAC Mapping
// =============================
#define V_MID   2.5f
#define V_AMP   1.0f
#define V_MIN   0.0f
#define V_MAX   5.0f

// =============================
// Audio buffer shared with ISR
// =============================
static float32_t audio_buffer[BUFFER_SIZE];
static volatile uint32_t audio_r = 0;   // ISR reads
static volatile uint32_t audio_w = 0;   // main writes

// =============================
// Sine table (test mode)
// =============================
#define SINE_TABLE_SIZE 512
static float32_t sine_table[SINE_TABLE_SIZE];

// =============================
// Function Prototypes
// =============================
void initTIM2_16kHz(void);
void generate_sine_table(void);

// =============================
// FFT/iFFT Buffers
// =============================
static float32_t X_full[2 * FRAME_SIZE];
static float32_t hann_win[FRAME_SIZE];

// ======================================
// Generate a 500 Hz sine wave table
// ======================================
void generate_sine_table(void)
{
    for (int n = 0; n < SINE_TABLE_SIZE; n++)
    {
        float phase = 2.0f * PI_F * n / SINE_TABLE_SIZE;
        sine_table[n] = sinf(phase);
    }

    printf("Sine table created: [%.3f, %.3f, %.3f...]\n",
        sine_table[0], sine_table[1], sine_table[2]);
}

// ======================================
// Timer 2 @ 16 kHz
// ======================================
void initTIM2_16kHz(void)
{
    // Enable clock
    RCC->APB1ENR1 |= RCC_APB1ENR1_TIM2EN;

    // For 16kHz update:
    // 80 MHz / (PSC+1) / (ARR+1) = 16000
    //
    // Your working setting:
    TIM2->PSC = 8;        // 80MHz / 2 = 40 MHz
    TIM2->ARR = 999;     // 40 MHz / 2500 = 16 kHz

    TIM2->CNT = 0;
    TIM2->DIER |= TIM_DIER_UIE;

    // Enable interrupt EXACTLY like your EXTI example
    NVIC->ISER[0] |= (1 << TIM2_IRQn);

    TIM2->CR1 |= TIM_CR1_CEN;
}

// ======================================
// TIMER 2 ISR: runs at 16 kHz
// Reads from circular buffer → DAC
// ======================================
void TIM2_IRQHandler(void)
{
    if (TIM2->SR & TIM_SR_UIF)
    {
        TIM2->SR &= ~TIM_SR_UIF;

        // Read next audio sample
        float32_t s = audio_buffer[audio_r];
        audio_r = (audio_r + 1) % BUFFER_SIZE;

        // Map from [-1,+1] → [0,5V]
        float32_t v = V_MID + V_AMP * s;

        if (v < V_MIN) v = V_MIN;
        if (v > V_MAX) v = V_MAX;

        setDAC(v);
    }
}

// ======================================
// Push one sample into audio buffer
// (main loop writes here)
// ======================================

static inline void audio_push(float32_t s)
{
    audio_buffer[audio_w] = s;
    audio_w = (audio_w + 1) % BUFFER_SIZE;
}

// ======================================
// MAIN
// ======================================
int main(void)
{
    configureFlash();
    configureClock();
    gpioEnable(GPIO_PORT_A);
    gpioEnable(GPIO_PORT_B);
    gpioEnable(GPIO_PORT_C);

    RCC->APB1ENR1 |= RCC_APB1ENR1_TIM2EN;
    RCC->APB2ENR |= RCC_APB2ENR_TIM15EN;  // for delay_millis
    initTIM(TIM15);                       // your known-good delay timer

    printf("\n===== AUDIO + IFFT PIPELINE START =====\n");
    printf("Sample rate: %.2f Hz\n", SAMPLE_RATE);

    // ---------------------------
    // 1. Generate sine test
    // ---------------------------
    generate_sine_table();

    // Adding stuff 
    configureDAC();

    // ADDIITON 
    printf("Pre-filling audio buffer...\n");
    for (int i = 0; i < BUFFER_SIZE; i++)
    {
    audio_buffer[i] = sine_table[i % SINE_TABLE_SIZE];
    }
    audio_w = BUFFER_SIZE;
    audio_r = 0;

    // ---------------------------
    // 2. Start audio ISR
    // ---------------------------
    initTIM2_16kHz();
    printf("TIM2 ISR running at 16 kHz.\n");

    __enable_irq();

    // Debug: produce 500 Hz sine
    uint32_t idx = 0;

    printf("Streaming 500 Hz test tone...\n");


    while (1)
    {
        static float phase = 0.0f;
        static const float phase_step = (500.0f * SINE_TABLE_SIZE) / SAMPLE_RATE;
        for (int i = 0; i < 256; i++)
        {
          float32_t s = sine_table[(uint32_t)phase & (SINE_TABLE_SIZE - 1)];
          phase += phase_step;
          if (phase >= SINE_TABLE_SIZE)
          phase -= SINE_TABLE_SIZE;
          audio_push(s);
        }


        // delay_millis(TIM15, 10);
        // printf("Buffered more samples...\n");
    }
}

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