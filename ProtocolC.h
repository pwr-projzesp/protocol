#pragma once

typedef nx_struct protocol_message
{
    nx_uint16_t seq_id;
    nx_uint16_t src;
    nx_uint16_t dest;
    nx_uint16_t cmd;
    nx_uint16_t data1;
    nx_uint16_t data2;
    nx_uint16_t data3;
} protocol_message_t;

typedef struct routing_entry
{
    uint16_t seq_id;
    uint16_t next;
    uint8_t hops;
} routing_entry_t;

// route request cache
typedef struct rrc_entry
{
    bool valid;
    uint16_t seq_id;
    uint16_t dest;
} rrc_entry_t;

#define PROTOCOL_MAX_MOTE_ID 32
#define PROTOCOL_CACHE_SIZE 8

#define PROTOCOL_CMD_LED 0
#define PROTOCOL_CMD_ACK 1
#define PROTOCOL_CMD_RRQ 2 // route request
#define PROTOCOL_CMD_RRR 3 // route request reply
#define PROTOCOL_CMD_TRC 4 // trace route
#define PROTOCOL_CMD_TRR 5 // trace route reply

bool is_routing_command(uint16_t command)
{
    return command == PROTOCOL_CMD_RRQ || command == PROTOCOL_CMD_RRR;
}

