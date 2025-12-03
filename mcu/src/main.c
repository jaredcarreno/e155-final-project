
#include "stm32l4xx.h"
#include "main.h"
#include <stdint.h>
#include <stdio.h>

#define SAMPLE_RATE 15000     // 15 kHz
#define DURATION_S  1         // 1 second
#define NUM_SAMPLES (SAMPLE_RATE * DURATION_S)     // 15000 samples
#define TX_BYTES    (NUM_SAMPLES * 2)              // 2 SPI bytes per sample
#define RX_BYTES    TX_BYTES                       // receive same amount

// Buffer for ALL received data
uint8_t spi_rx_buffer[RX_BYTES];


// =====================================================
// sendWave() – send 1 sec of square wave, padded to 16 bits,
// and capture ALL returned bytes.
// =====================================================
void sendWave(float waveFreqHz)
{
    uint32_t halfPeriod = (uint32_t)(SAMPLE_RATE / (2.0f * waveFreqHz));
    if (halfPeriod == 0) return;

    uint8_t hi = 0x64;
    uint8_t lo = 0x00;
    uint8_t current = hi;
    uint32_t counter = 0;
    uint32_t rxIndex = 0;

    for (uint32_t i = 0; i < NUM_SAMPLES; i++)
    {
        // toggle square wave
        if (counter >= halfPeriod)
        {
            current = (current == hi) ? lo : hi;
            counter = 0;
        }
        counter++;

        // -------- SEND 16 BITS --------
        uint8_t rx1 = spiSendReceive(0x00);     // MSB padding
        uint8_t rx2 = spiSendReceive(current);  // actual square wave 8-bit sample

        // -------- STORE RETURNED DATA --------
        spi_rx_buffer[rxIndex++] = rx1;
        spi_rx_buffer[rxIndex++] = rx2;
    }
}


// =====================================================
// Helper: Print rx buffer in 32-bit words
// =====================================================
void print_rx_32bit_chunks(void)
{
    printf("\n--- Returned SPI Data (32-bit hex words) ---\n");

    uint32_t totalWords = RX_BYTES / 4;

    for (uint32_t i = 0; i < totalWords; i++)
    {
        uint32_t b0 = spi_rx_buffer[i*4 + 0];
        uint32_t b1 = spi_rx_buffer[i*4 + 1];
        uint32_t b2 = spi_rx_buffer[i*4 + 2];
        uint32_t b3 = spi_rx_buffer[i*4 + 3];

        uint32_t word =
              (b0 << 24)
            | (b1 << 16)
            | (b2 << 8)
            | (b3);

        printf("0x%08lX\n", word);
    }
}


// =====================================================
// MAIN
// =====================================================
int main(void)
{
    SystemInit();
    initSPI(2, 0, 0);   // example config: baud=2, CPOL=0, CPHA=0

    printf("Sending 1 kHz square wave...\n");
    sendWave(1000.0f);

    printf("Transmission complete.\n");

    print_rx_32bit_chunks();

    // while (1);
}
