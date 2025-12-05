// Main source file for Autotune project
// Emma Angel, Jared Carreno, Shreya Jampana
// eangel@hmc.edu, jcarreno@hmc.edu, sjampana@hmc.edu
// 12/5/2025
#include "stm32l4xx.h"
#include "arm_math.h"
#include "arm_const_structs.h"
#include "main.h"
#include <stdint.h>
#include <string.h>
#include <stdio.h>
#include <math.h>

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