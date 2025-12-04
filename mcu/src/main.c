#include "stm32l4xx.h"
#include "arm_math.h"
#include "arm_const_structs.h"
#include "main.h"
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

// --- ADC DMA BUFFER (64 samples of 8-bit data) ---
volatile uint8_t adc_block[64];

// --- SPI RX BUFFER (64 bins × 4 bytes = 256 bytes) ---
uint8_t spi_rx_block[256];

// --- FFT SPACE (64 complex floats = 128 floats) ---
float32_t X_fft[2 * FFT_N];

// Hann window + OLA buffer
float32_t hann_win[FFT_N];
float32_t ola_buffer[OUTBUF_SIZE];
uint32_t  ola_pos = 0;

// DMA flag: 1 = 64-sample block ready
volatile uint8_t dma_flag = 0;
void  DMA_Init();
void DMA_Config();
void ADC_Init();


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
void DMA1_Channel1_IRQHandler(void)
{
    if (DMA1->ISR & DMA_ISR_TCIF1)
    {
        DMA1->IFCR = DMA_IFCR_CTCIF1;

        dma_flag = 1;   // 64-sample block ready
    }
}
void spi_send_block_64_and_receive_fft(uint8_t *tx, uint8_t *rx)
{
    initSPI(2,0,0);   // FPGA SPI mode

    for (int i = 0; i < 64; i++)
    {
        uint8_t r0 = spiSendReceive(tx[i]);
        rx[4*i + 0] = r0;

        uint8_t r1 = spiSendReceive(0x00);
        rx[4*i + 1] = r1;

        uint8_t r2 = spiSendReceive(0x00);
        rx[4*i + 2] = r2;

        uint8_t r3 = spiSendReceive(0x00);
        rx[4*i + 3] = r3;
    }
}
int main(void)
{
    configureFlash();
    configureClock();

    gpioEnable(GPIO_PORT_A);
    gpioEnable(GPIO_PORT_B);
    gpioEnable(GPIO_PORT_C);

    RCC->APB2ENR |= RCC_APB2ENR_TIM15EN;
    initTIM(TIM15);

    init_hann_64();
    memset(ola_buffer, 0, sizeof(ola_buffer));

    DMA_Init();
    DMA_Config();
    ADC_Init();

    initSPI(5,0,0);  // initial FPGA SPI

    while (1)
    {
        // If button NOT pressed: stop ADC
        if (!digitalRead(PA5))
        {
            ADC1->CR |= ADC_CR_ADSTP;
            while (ADC1->CR & ADC_CR_ADSTP);

            DMA1_Channel1->CCR &= ~DMA_CCR_EN;
            dma_flag = 0;
            continue;
        }
        else
        {
            if (!(ADC1->CR & ADC_CR_ADSTART))
            {
                DMA1_Channel1->CNDTR = 64;
                DMA1_Channel1->CCR |= DMA_CCR_EN;
                ADC1->CR |= ADC_CR_ADSTART;
            }
        }

        if (dma_flag)
        {
            dma_flag = 0;

            // --- SPI Tx/Rx ---
            spi_send_block_64_and_receive_fft((uint8_t*)adc_block,
                                              spi_rx_block);

            // --- FFT Post-Processing ---
            fft_postprocess_phase_quantize_64(spi_rx_block, X_fft);

            // --- IFFT ---
            run_ifft_64(X_fft);

            // --- DAC Output ---
            process_ifft_frame_and_output(X_fft);
        }
    }
}

void ADC_Init(void)
{
    /* --- 1. Enable clocks --- */
    RCC->AHB2ENR |= (1<<0) | (1<<2) | (1<<13);  
    // GPIOA | GPIOC | ADC enable

    /* --- 2. Set ADC clock source (System Clock = 80 MHz) --- */
    RCC->CCIPR &= ~(3 << 28);
    RCC->CCIPR |=  (3 << 28);     // ADC clock = SYSCLK
    //  ADC1_COMMON->CCR |= (10<<18); // Set ADC Prescaler to 128, 80Mhz/128 = 625kHz
    // Need to disable ADC first maybe?


    /* --- 3. Configure ADC prescaler (safe: /4) --- */ // FIX THE PRESCALER
    ADC1_COMMON->CCR &= ~(0xF << 18); 
    ADC1_COMMON->CCR |=  (11 << 18);    // changing prescaler to 256

    /* --- 4. ADC power-up sequence --- */
    ADC1->CR &= ~(1<<29);     // disable deep power-down
    ADC1->CR |=  (1<<28);     // enable voltage regulator
    // delay_millis(TIM15, 10);             // regulator stabilization (required)

    /* --- 5. Resolution, alignment, continuous mode --- */
    ADC1->CFGR &= ~(2 << 3);  // 12-bit, I WANT 8 BIT RES, changing to 2 should be 8-bit res
    ADC1->CFGR |=  (1 << 13); // continuous conversion mode
    ADC1->CFGR &= ~(1 << 5);  // right alignment

    /* --- 6. Sampling time for channel 5 --- */
    ADC1->SMPR1 &= ~(7 << 15);         // clear SMP5
    ADC1->SMPR1 |=  (2 << 15);         // SMP5 = 12.5 cycles (example), I DO WANT 12.5 CYCLES

    /* --- 7. Configure GPIO for analog input (CH5 = PC0) --- */
    GPIOC->MODER &= ~(3 << 0);
    GPIOC->MODER |=  (3 << 0);         // PC0 → analog mode

    /* --- 8. DMA settings (circular mode) --- */

    ADC1->CFGR |=  (1 << 0);           // DMAEN
    ADC1->CFGR |=  (1 << 1);           // DMACFG = circular mode, (same are circular double buffer

    /* --- 9. Configure regular sequence for ONE channel (length = 1) --- */
    ADC1->SQR1 &= ~0xF;                // L = 0 (1 conversion)
    ADC1->SQR1 &= ~(0x1F << 6);        
    ADC1->SQR1 |=  (5 << 6);           // Rank 1 = CH5

    /* --- 10. Enable ADC --- */
    ADC1->ISR |= (1<<0);               // clear ADRDY
    ADC1->CR  |= (1<<0);               // enable ADC

    while (!(ADC1->ISR & (1<<0)));     // wait for ADC ready

    /* --- 11. Start conversions --- */
    // ADDING BUTTON - wait until button to start ADC
    // ADC1->CR |= (1<<2);                // ADSTART
}


void DMA_Init(void)
{
    RCC->AHB1ENR |= (1 << 0); // enable DMA1

    DMA1_Channel1->CCR &= ~(1 << 0); // disable channel

    // Direction = Peripheral-to-Memory (0)
    DMA1_Channel1->CCR &= ~(1 << 4);

    DMA1_Channel1->CCR |=  (1 << 5);  // circular mode
    DMA1_Channel1->CCR |=  (1 << 7);  // memory increment

    // PSIZE = 16-bit, MSIZE = 16-bit THIS NEEDS TO BE 8 bt

    DMA1_Channel1->CCR &= ~((1 << 8) | (1 << 10)); // setting this to 8 bit size 
    // DMA1_Channel1->CCR |=  ((0 << 8) | (0 << 10));

    // Adding interrupt configuration
    DMA1_Channel1->CCR |= (1 << 1);  // TCIE (full transfer)
    DMA1_Channel1->CCR |= (1 << 2);  // HTIE (half transfer)

    NVIC_EnableIRQ(DMA1_Channel1_IRQn);
}




void DMA_Config(void)
{
    DMA1_Channel1->CCR &= ~(1 << 0); // disable DMA

    DMA1_Channel1->CNDTR = 1024; // size of transfer 
    DMA1_Channel1->CPAR  = (uint32_t)&ADC1->DR; // address of peripheral
    DMA1_Channel1->CMAR  = (uint32_t)adc_block; // address of memory buffer

    DMA1_Channel1->CCR |= (1 << 0); // enable channel
}

