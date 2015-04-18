#pragma once

typedef nx_struct protocol_message
{
    nx_uint16_t seq_id;
    nx_uint16_t src;
    nx_uint16_t dest;
    nx_uint16_t cmd;
} protocol_message_t;

#define PROTOCOL_MAX_MOTE_ID 32

#define PROTOCOL_CMD_LED 0
#define PROTOCOL_CMD_ACK 1

