#include "ProtocolC.h"

module ProtocolC
{
    uses
    {
        interface Boot;
        interface Leds;
        interface Receive as ReceiveREQ;
        interface Timer<TMilli> as Timer;
        interface Timer<TMilli> as RetransmitTimer;
        interface AMSend;
        interface Packet;
        interface SplitControl as AMControl;
    }
}

implementation
{
    message_t packet;

    message_t retransmit_packet;
    bool retransmit_pending = FALSE;

    nx_uint16_t curr_seq_id[PROTOCOL_MAX_MOTE_ID];
    nx_uint16_t own_seq_id;
    uint8_t target = 0;

    event void Boot.booted()
    {
        int i;

        call AMControl.start();
        own_seq_id = 0;

        for (i = 0; i < PROTOCOL_MAX_MOTE_ID; ++i)
        {
            curr_seq_id[i] = 0;
        }
    }

    event void AMControl.startDone(error_t err)
    {
        if (err == SUCCESS)
        {
            call Timer.startPeriodic(250);
        }
        else
        {
            call AMControl.start();
        }
    }

    event void AMControl.stopDone(error_t err)
    {
    }

    event void AMSend.sendDone(message_t * msg, error_t err)
    {
    }

    void send_ack(nx_uint16_t seq_id, nx_uint16_t src)
    {
        int i;
        protocol_message_t protomsg;
        uint8_t * data = (uint8_t *)&protomsg;

        protomsg.seq_id = seq_id;
        protomsg.src = TOS_NODE_ID;
        protomsg.dest = src;
        protomsg.cmd = PROTOCOL_CMD_ACK;

        for (i = 0; i < sizeof(protocol_message_t); ++i)
        {
            packet.data[i] = data[i];
        }

        call AMSend.send(AM_BROADCAST_ADDR, &packet, sizeof(protocol_message_t));
    }

    event message_t * ReceiveREQ.receive(message_t * msg, void * payload, uint8_t len)
    {
        protocol_message_t * protomsg = (protocol_message_t *)msg->data;

        switch (protomsg->cmd)
        {
        case PROTOCOL_CMD_LED:
            if (protomsg->dest == TOS_NODE_ID)
            {
                call Leds.led0Toggle();
                send_ack(protomsg->seq_id, protomsg->src);
            }

            else if (protomsg->src == TOS_NODE_ID)
            {
                // received our own message back. do nothing.
                call Leds.led1Toggle();
            }

            else if (protomsg->seq_id > curr_seq_id[protomsg->src])
            {
                int i;

                curr_seq_id[protomsg->src] = protomsg->seq_id;
                call Leds.led2Toggle();

                if (!retransmit_pending)
                {
                    retransmit_pending = TRUE;
                    call RetransmitTimer.startOneShot(50);
                    for (i = 0; i < sizeof(protocol_message_t); ++i)
                    {
                        retransmit_packet.data[i] = msg->data[i];
                    }
                }
            }

            break;

        case PROTOCOL_CMD_ACK:
            {
                protocol_message_t * pending = (protocol_message_t *)retransmit_packet.data;
                if (retransmit_pending && pending->dest == protomsg->src && pending->seq_id <= protomsg->seq_id)
                {
                    retransmit_pending = FALSE;
                }
            }
        }

        return msg;
    }

    event void Timer.fired()
    {
        if (TOS_NODE_ID == 1)
        {
            protocol_message_t protomsg;
            uint8_t * data = (uint8_t *)&protomsg;
            int i;

            protomsg.seq_id = own_seq_id++;
            protomsg.src = TOS_NODE_ID;
            protomsg.dest = 2 + target;
            protomsg.cmd = PROTOCOL_CMD_LED;
            target = !target;

            for (i = 0; i < sizeof(protocol_message_t); ++i)
            {
                packet.data[i] = data[i];
            }

            call AMSend.send(AM_BROADCAST_ADDR, &packet, sizeof(protocol_message_t));
            call Leds.led2Toggle();
        }
    }

    event void RetransmitTimer.fired()
    {
        if (retransmit_pending)
        {
            retransmit_pending = FALSE;
            call AMSend.send(AM_BROADCAST_ADDR, &retransmit_packet, sizeof(protocol_message_t));
            call Leds.led1Toggle();
        }
    }
}

