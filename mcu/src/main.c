// tim2_sine_output.c
// Timer 2 interrupt at 16 kHz → output a 500 Hz sine wave via setDAC()
// Based on your verified working Timer2 ISR code

#include <stdio.h>
#include <math.h>
#include "main.h"
#include "arm_math.h"
#include "arm_const_structs.h"

#define SAMPLE_RATE     16000.0f   // Hz
#define SINE_FREQ       500.0f     // Hz
#define TABLE_SIZE      512        // Must be power of 2
#define PI_F            3.14159265358979f

// DAC output mapping
#define V_MIN           0.0f
#define V_MAX           5.0f
#define V_MID           2.5f       // center (DAC mid rail)
#define V_AMP           1.0f       // 1 V peak sine

static float32_t sine_table[TABLE_SIZE];
static volatile uint32_t table_idx = 0;
volatile uint32_t tim2_count = 0;

// Forward declarations
void initTIM2_16kHz(void);
void generate_sine_table(void);

int main(void)
{
    configureFlash();
    configureClock();
    gpioEnable(GPIO_PORT_A);
    gpioEnable(GPIO_PORT_B);
    gpioEnable(GPIO_PORT_C);

    // =================================
    // Enable TIM2 clock
    // =================================
    RCC->APB1ENR1 |= RCC_APB1ENR1_TIM2EN;

    // Build sine table
    generate_sine_table();
    RCC->APB2ENR |= (RCC_APB2ENR_TIM15EN);
    initTIM(TIM15);

    // Init DAC (your function)
    configureDAC();

    // Start 16 kHz ISR
    initTIM2_16kHz();

    // Enable global interrupts
    __enable_irq();

    printf("===== Timer2 16 kHz Sine Output Test =====\n");

    while(1)
    {
        delay_millis(TIM15, 1000);
        printf("Main alive... ISR count = %lu\n", tim2_count);
    }
}


// ============================================================
// Generate 500 Hz sine lookup table
// ============================================================
void generate_sine_table(void)
{
    for (int n = 0; n < TABLE_SIZE; n++)
    {
        float phase = 2.0f * PI_F * n / TABLE_SIZE;
        sine_table[n] = sinf(phase);
    }

    printf("Sine table created: [%.3f, %.3f, %.3f...]\n",
           sine_table[0], sine_table[1], sine_table[2]);
}


// ============================================================
// Configure TIM2 for 16 kHz interrupts
// ============================================================
void initTIM2_16kHz(void)
{
    TIM2->PSC = 4;       // 80MHz / (4+1) = 16 MHz
    TIM2->ARR = 999;     // 16MHz / (999+1) = 16000 Hz
    TIM2->CNT = 0;

    TIM2->DIER |= TIM_DIER_UIE;   // Enable update interrupt

    // EXACT NVIC enable method verified earlier
    NVIC->ISER[0] |= (1 << TIM2_IRQn);

    TIM2->CR1 |= TIM_CR1_CEN;     // Start timer
}


// ============================================================
// TIMER 2 INTERRUPT — 16 kHz audio sample generator
// ============================================================
void TIM2_IRQHandler(void)
{
    if (TIM2->SR & TIM_SR_UIF)
    {
        TIM2->SR &= ~TIM_SR_UIF;   // Clear flag

        tim2_count++;

        // -------------------------------
        // Get sample from sine table
        // -------------------------------
        float s = sine_table[table_idx];

        table_idx++;
        if (table_idx >= TABLE_SIZE)
            table_idx = 0;

        // -------------------------------
        // Convert (-1..+1) to DAC voltage
        // -------------------------------
        float v = V_MID + V_AMP * s;

        if (v < V_MIN) v = V_MIN;
        if (v > V_MAX) v = V_MAX;

        // -------------------------------
        // Output to DAC
        // -------------------------------
        setDAC(v);
    }
}
