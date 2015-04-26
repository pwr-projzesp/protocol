#pragma once

typedef nx_struct protocol_message
{
    nx_uint16_t seq_id;
    nx_uint16_t src;
    nx_uint16_t dest;
    nx_uint16_t cmd;
    nx_uint16_t data1;
    nx_uint16_t data2;
} protocol_message_t;

typedef struct routing_entry
{
    uint16_t seq_id;
    uint16_t next;
    uint8_t hop;
} routing_entry_t;

// route request cache
typedef struct rrc_entry
{
    uint16_t seq_id;
    uint16_t src;
    uint16_t dest;
    uint8_t hop;
} rrc_entry_t;

#define PROTOCOL_MAX_MOTE_ID 32
#define PROTOCOL_CACHE_SIZE 8

#define PROTOCOL_CMD_LED 0
#define PROTOCOL_CMD_ACK 1
#define PROTOCOL_CMD_RRQ 2 // route request
#define PROTOCOL_CMD_RRR 3 // route request reply

