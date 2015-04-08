#include "printf.h"

typedef struct _protocol_message
{
    uint8_t dest;
    uint8_t src;
    uint8_t cmd;
    uint8_t data[1];
} protocol_message;

typedef struct _neighbour_desc
{
    uint8_t neighbour_id;
    uint8_t priority;
} neighbour_desc;

module ProtocolC @safe()
{
    uses
    {
        interface Boot;
        // blink on some communication action
        interface Leds;
        interface Receive as ReceiveREQ;
        interface Timer<TMilli> as TimeoutTimer;
        interface Timer<TMilli> as SendTimer;
        interface AMSend;
        interface Packet;
        interface SplitControl as AMControl;
    }

    provides
    {
        interface ProtocolSend;
        interface Receive;
    }
}

implementation
{
    bool send_pending = FALSE;
    bool message_pending = TRUE;
    // unused right now
    neighbour_desc neighbours[16] = { { 0, 0 }, { 1, 0 }, { 2, 0 } };
    uint8_t neighbour_count = 3;

    message_t proto_msg;

    event void Boot.booted()
    {
        call AMControl.start();
    }

    event void AMControl.startDone(error_t err)
    {
        if (err == SUCCESS)
        {
            call SendTimer.startPeriodic(1000);
            call TimeoutTimer.startPeriodic(100);
        }
        else
        {
            call AMControl.start();
        }
    }

    event void AMControl.stopDone(error_t err)
    {
    }

    task void resend()
    {
        if (message_pending && !send_pending)
        {
            if (call AMSend.send(AM_BROADCAST_ADDR, &proto_msg, call Packet.payloadLength(&proto_msg)) == SUCCESS)
            {
                send_pending = TRUE;
                message_pending = FALSE;
            }
        }
    }

    event void TimeoutTimer.fired()
    {
        if (message_pending)
        {
            post resend();
        }
    }

    message_t dummy;
    bool diode = FALSE;

    event void SendTimer.fired()
    {
        dummy.data[0] = diode;
        diode = !diode;
        call ProtocolSend.send(1, &dummy, 1); //call Packet.payloadLength(&dummy)):
    }

    event void AMSend.sendDone(message_t * message, error_t error)
    {
        if (error == SUCCESS)
        {
            send_pending = FALSE;
        }
        else
        {
            message_pending = TRUE;
        }
    }

    error_t send_message(uint8_t source, uint8_t destination, message_t * message, uint8_t length)
    {
        int i = 0;
        protocol_message * msg = (protocol_message *)&proto_msg;
        msg->dest = destination;
        msg->src = source;
        for (i = 0; i < length; ++i)
        {
            msg->data[i] = message->data[i];
        }
        send_pending = TRUE;
        return call AMSend.send(AM_BROADCAST_ADDR, &proto_msg, call Packet.payloadLength(&proto_msg));
    }

    event message_t * ReceiveREQ.receive(message_t * msg, void * payload, uint8_t len)
    {
        protocol_message * pmsg = (protocol_message *)msg->data;
        if (TOS_NODE_ID == 1 && pmsg->dest == 1)
        {
            if (pmsg->src == 2)
            {
                if (pmsg->data[0] == TRUE)
                {
                    call Leds.led1On();
                }

                else
                {
                    call Leds.led1Off();
                }
            }

            else if (pmsg->src == 3)
            {
                if (pmsg->data[0] == TRUE)
                {
                    call Leds.led2On();
                }

                else
                {
                    call Leds.led2Off();
                }
            }
        }

        call Leds.led0Toggle();

        if (pmsg->dest != TOS_NODE_ID)
        {
            send_message(pmsg->src, pmsg->dest, msg, len);
        }

        return msg;
    }

    command error_t ProtocolSend.send(uint8_t destination, message_t * message, uint8_t length)
    {
        return send_message(TOS_NODE_ID, destination, message, length);
    }
}

