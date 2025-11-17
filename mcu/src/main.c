#include <string.h>
#include <stdlib.h>
#include <stdio.h>
#include "main.h"

// the thingies for the HAL drivers
ADC_HandleTypeDef hadc1;      // ADC1
DMA_HandleTypeDef hdma_adc1;  // DMA1
TIM_HandleTypeDef htim6;      // TIM6

// ADC buffer for samples
#define ADC_BUF_LEN  512  // using 512 for FFT point??? 
uint16_t adc_buf[ADC_BUF_LEN];

// ADC config function using HAL drivers 
// chat wrote this nobody panic
void ADC_Config(void)
{
    /* 1. Enable clocks */
    __HAL_RCC_ADC_CLK_ENABLE();
    __HAL_RCC_DMA1_CLK_ENABLE();
    __HAL_RCC_GPIOA_CLK_ENABLE();   // why are we using GPIOA -- should look into this
    __HAL_RCC_TIM6_CLK_ENABLE();

    /* 2. Configure ADC pin PA0 (ADC1_IN5 example) */
    // TODO: what if I want to use channel 1 like a sane person and not channel 5
    // Can probably replace this code withthe GPIO libaries OR 
    // add the GPIO HAL driver but def a way to do this with GPIO lib, do need to the alt function thing tho feels like a lot of work 
    GPIO_InitTypeDef gpio = {0};                // creates HAL structure
    gpio.Pin = GPIO_PIN_0;                      // PA0, ADC channel 5 is connected to PA0
    gpio.Mode = GPIO_MODE_ANALOG_ADC_CONTROL;   // Analog mode + ADC control over pin
    gpio.Pull = GPIO_NOPULL;                    // No pull ups/downs
    HAL_GPIO_Init(GPIOA, &gpio);                // Apply the configuration to GPIOA

    /* 3. Configure DMA channel */
    hdma_adc1.Instance = DMA1_Channel1;
    hdma_adc1.Init.Request = DMA_REQUEST_0;  // ADC1 request
    hdma_adc1.Init.Direction = DMA_PERIPH_TO_MEMORY;
    hdma_adc1.Init.PeriphInc = DMA_PINC_DISABLE;
    hdma_adc1.Init.MemInc = DMA_MINC_ENABLE;
    hdma_adc1.Init.PeriphDataAlignment = DMA_PDATAALIGN_HALFWORD;
    hdma_adc1.Init.MemDataAlignment = DMA_MDATAALIGN_HALFWORD;
    hdma_adc1.Init.Mode = DMA_CIRCULAR;
    hdma_adc1.Init.Priority = DMA_PRIORITY_HIGH;

    HAL_DMA_Init(&hdma_adc1);
    __HAL_LINKDMA(&hadc1, DMA_Handle, hdma_adc1);

    /* 4. Configure ADC */
    hadc1.Instance = ADC1;
    hadc1.Init.ClockPrescaler = ADC_CLOCK_ASYNC_DIV1;
    hadc1.Init.Resolution = ADC_RESOLUTION_12B;
    hadc1.Init.DataAlign = ADC_DATAALIGN_RIGHT;
    hadc1.Init.ScanConvMode = ADC_SCAN_DISABLE;
    hadc1.Init.EOCSelection = ADC_EOC_SINGLE_CONV;
    hadc1.Init.LowPowerAutoWait = DISABLE;
    hadc1.Init.ContinuousConvMode = DISABLE;  // IMPORTANT: timer triggers conversions
    hadc1.Init.ExternalTrigConv = ADC_EXTERNALTRIG_T6_TRGO;
    hadc1.Init.ExternalTrigConvEdge = ADC_EXTERNALTRIGCONVEDGE_RISING;
    hadc1.Init.DMAContinuousRequests = ENABLE;

    HAL_ADC_Init(&hadc1);

    /* 5. Configure ADC channel */
    ADC_ChannelConfTypeDef sConfig = {0};
    sConfig.Channel = ADC_CHANNEL_5;   // PA0
    sConfig.Rank = ADC_REGULAR_RANK_1;
    sConfig.SamplingTime = ADC_SAMPLETIME_12CYCLES_5;
    HAL_ADC_ConfigChannel(&hadc1, &sConfig);

    /* 6. Timer 6 @ 48 kHz TRGO */
    // TIM6 runs from APB1 @ 80 MHz assumed
    htim6.Instance = TIM6;
    htim6.Init.Prescaler = 79;    // 80MHz/80 = 1MHz
    htim6.Init.Period = 1000000/48000 - 1;  // =20-1 => 48 kHz
    htim6.Init.CounterMode = TIM_COUNTERMODE_UP;
    HAL_TIM_Base_Init(&htim6);

    // Set TRGO on update event
    TIM_MasterConfigTypeDef master = {0};
    master.MasterOutputTrigger = TIM_TRGO_UPDATE;
    master.MasterSlaveMode = TIM_MASTERSLAVEMODE_DISABLE;
    HAL_TIMEx_MasterConfigSynchronization(&htim6, &master);

    /* 7. Start peripherals */
    HAL_TIM_Base_Start(&htim6);
    HAL_ADC_Start_DMA(&hadc1, (uint32_t*)adc_buf, ADC_BUF_LEN);
}



int main(void){
    // setting up ADC config 





}