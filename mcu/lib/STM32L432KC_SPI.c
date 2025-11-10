// STM32L432KC_SPI.c
// Emma Angel
// eangel@hmc.edu
// 10/16/2025
// SPI functions to initialize and send/recieve

#include "STM32L432KC_SPI.h"
#include "STM32L432KC_GPIO.h"
#include "DS1722.h"


void initSPI(int br, int cpol, int cpha){
    // adding in 
    RCC->AHB2ENR |= (RCC_AHB2ENR_GPIOAEN | RCC_AHB2ENR_GPIOBEN);
    // SPI clock 
    RCC->APB2ENR |= _VAL2FLD(RCC_APB2ENR_SPI1EN, 1);
    // pin Modes
    pinMode(SPI_SCLK, GPIO_ALT);
    pinMode(SPI_CIPO, GPIO_ALT);
    pinMode(SPI_COPI, GPIO_ALT);
    pinMode(SPI_CS, GPIO_OUTPUT);

    // Set GPIO output speed 
    GPIOB->OSPEEDR |= (GPIO_OSPEEDR_OSPEED3); // Why why we do this?

    // Set AFRL AF5
    GPIOB->AFR[0] |= _VAL2FLD(GPIO_AFRL_AFSEL3, 5);
    GPIOB->AFR[0] |= _VAL2FLD(GPIO_AFRL_AFSEL4, 5);
    GPIOB->AFR[0] |= _VAL2FLD(GPIO_AFRL_AFSEL5, 5);

    // SPI configuration
    SPI1->CR1 |= _VAL2FLD(SPI_CR1_BR, br); // Set baud rate
    // 
    SPI1->CR1 |= (SPI_CR1_MSTR); // Master configuration
    // adding
    SPI1->CR1 &= ~(SPI_CR1_CPOL | SPI_CR1_CPHA | SPI_CR1_LSBFIRST | SPI_CR1_SSM);
    SPI1->CR1 |= _VAL2FLD(SPI_CR1_CPHA, cpha); // Set CPHA
    SPI1->CR1 |= _VAL2FLD(SPI_CR1_CPOL, cpol); // Set SPOL
    SPI1->CR2 |= _VAL2FLD(SPI_CR2_DS, 0b0111); // Set data size to 8-bit
    // changing 
    SPI1->CR2 |= (SPI_CR2_FRXTH | SPI_CR2_SSOE);
    // SPI1->CR2 |= _VAL2FLD(SPI_CR2_FRXTH, 0b1); // Set  FIFO reception threshold


    SPI1->CR1 |= (SPI_CR1_SPE); // Enable SPI

}

char spiSendReceive(char send){
    // trasmist buffer empty
    while(!(SPI1->SR & SPI_SR_TXE));
    // Load the char send into the data register
    *(volatile char *) (&SPI1->DR) = send;
    // Wait until the recieve buffer is empty
    while(!(SPI1->SR & SPI_SR_RXNE));
    // load the recieved data into the recieve char
    char recieve = (volatile char) SPI1->DR;
    // Return the CIPO data
    return recieve;
}
