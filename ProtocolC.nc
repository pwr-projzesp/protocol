#include "ProtocolC.h"
#include "printf.h"

module ProtocolC
{
    uses
    {
        interface Boot;
        interface Leds;
        interface Receive as ReceiveREQ;
        interface Timer<TMilli> as Timer;
        interface Timer<TMilli> as RRQTimer;
        interface Timer<TMilli> as ACKTimer;
        interface AMSend;
        interface Packet;
        interface SplitControl as AMControl;
    }
}

implementation
{
    message_t packet;

    bool pending_rrq = FALSE;
    nx_uint16_t pending_rrq_seq_id;
    nx_uint16_t pending_rrq_dest;
    bool pending_rrq_flush = FALSE;

    bool pending_ack = FALSE;
    nx_uint16_t pending_ack_seq_id;
    nx_uint16_t pending_ack_src;

    bool pending_acks[PROTOCOL_MAX_MOTE_ID];
    uint8_t unacked_counts[PROTOCOL_MAX_MOTE_ID];

    nx_uint16_t curr_seq_id[PROTOCOL_MAX_MOTE_ID];
    nx_uint16_t own_seq_id;
    uint8_t target = 2;

    routing_entry_t routing_entries[PROTOCOL_MAX_MOTE_ID];

    event void Boot.booted()
    {
        int i;

        call AMControl.start();
        own_seq_id = 0;

        for (i = 0; i < PROTOCOL_MAX_MOTE_ID; ++i)
        {
            curr_seq_id[i] = 0;
            routing_entries[i].seq_id = 0;
            unacked_counts[i] = 0;
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

    void setup_pending_ack(nx_uint16_t seq_id, nx_uint16_t src)
    {
        pending_acks[src] = TRUE;
        call ACKTimer.startOneShot(50);
    }

    void send_message(nx_uint16_t seq_id, nx_uint16_t dest, nx_uint16_t cmd, nx_uint16_t data1, nx_uint16_t data2)
    {
        int i;
        protocol_message_t protomsg;
        uint8_t * ptr = (uint8_t *)&protomsg;

        protomsg.seq_id = seq_id;
        protomsg.src = TOS_NODE_ID;
        protomsg.dest = dest;
        protomsg.cmd = cmd;
        protomsg.data1 = data1;
        protomsg.data2 = data2;

        for (i = 0; i < sizeof(protocol_message_t); ++i)
        {
            packet.data[i] = ptr[i];
        }

        call AMSend.send(AM_BROADCAST_ADDR, &packet, sizeof(protocol_message_t));

        if (!is_routing_command(cmd) && cmd != PROTOCOL_CMD_ACK)
        {
            setup_pending_ack(seq_id, dest);
        }
    }

    void send_ack(nx_uint16_t seq_id, nx_uint16_t src)
    {
        printf("sending ack, seq_id: %d, dest: %d\n", seq_id, src);
        printfflush();
        send_message(seq_id, src, PROTOCOL_CMD_ACK, 0, 0);
    }

    task void send_ack_delayed_task()
    {
        if (pending_ack)
        {
            pending_ack = TRUE;
            send_ack(pending_ack_seq_id, pending_ack_src);
        }
    }

    void send_ack_delayed(nx_uint16_t seq_id, nx_uint16_t src)
    {
        if (!pending_ack)
        {
            pending_ack = TRUE;
            pending_ack_seq_id = seq_id;
            pending_ack_src = src;
            post send_ack_delayed_task();
        }
    }

    void send_rrq_reply(nx_uint16_t seq_id, nx_uint16_t dest)
    {
        printf("sending rrq reply, seq_id: %d, dest: %d\n", seq_id, dest);
        printfflush();
        send_message(seq_id, dest, PROTOCOL_CMD_RRR, TOS_NODE_ID, 0);
    }

    void send_routing_request(nx_uint16_t seq_id, nx_uint16_t dest, bool flush)
    {
        printf("seding rrq, seq_id: %d, dest: %d\n", seq_id, dest);
        printfflush();
        call Leds.led1Toggle();
        send_message(seq_id, 0, PROTOCOL_CMD_RRQ, dest, flush);
    }

    void send_routing_request_delayed(nx_uint16_t seq_id, nx_uint16_t dest, bool flush)
    {
        if (!pending_rrq)
        {
            pending_rrq = TRUE;
            pending_rrq_seq_id = seq_id;
            pending_rrq_dest = dest;
            pending_rrq_flush = flush;

            call RRQTimer.startOneShot(50);
        }
    }

    void send_routing_reply(nx_uint16_t seq_id, nx_uint16_t dest, nx_uint16_t src, nx_uint16_t hops)
    {
        printf("sending routing reply, seq_id: %d, dest: %d, src: %d, hops: %d\n", seq_id, dest, src, hops);
        printfflush();
        send_message(seq_id, dest, PROTOCOL_CMD_RRR, src, hops);
    }

    event message_t * ReceiveREQ.receive(message_t * msg, void * payload, uint8_t len)
    {
        protocol_message_t * protomsg = (protocol_message_t *)msg->data;

        if (!routing_entries[protomsg->src].seq_id || routing_entries[protomsg->src].hops)
        {
            printf("saving route to %d\n", protomsg->src);
            routing_entries[protomsg->src].seq_id = protomsg->seq_id;
            routing_entries[protomsg->src].next = protomsg->src;
            routing_entries[protomsg->src].hops = 0;
        }

        switch (protomsg->cmd)
        {
        case PROTOCOL_CMD_LED:
            if (protomsg->dest == TOS_NODE_ID)
            {
                if (protomsg->data1 == TOS_NODE_ID)
                {
                    call Leds.led0Toggle();
                    send_ack(protomsg->seq_id, protomsg->src);
                }

                // ...the message came back...
                else if (protomsg->data2 == TOS_NODE_ID)
                {
                    routing_entries[protomsg->data1].seq_id = 0;
                    send_routing_request(++own_seq_id, protomsg->data1, TRUE);
                }

                else if (protomsg->seq_id > curr_seq_id[protomsg->data2])
                {
                    curr_seq_id[protomsg->data2] = protomsg->seq_id;
                    call Leds.led2Toggle();

                    if (routing_entries[protomsg->data1].seq_id)
                    {
                        send_message(protomsg->seq_id, routing_entries[protomsg->data1].next, protomsg->cmd, protomsg->data1, protomsg->data2);
                        send_ack_delayed(protomsg->seq_id, protomsg->src);
                    }

                    else
                    {
                        send_routing_request(++own_seq_id, protomsg->data1, FALSE);
                    }
                }
            }

            else if (protomsg->data1 == TOS_NODE_ID)
            {
                send_routing_request(++own_seq_id, protomsg->src, FALSE);
            }

            break;

        case PROTOCOL_CMD_ACK:
            if (protomsg->dest == TOS_NODE_ID)
            {
                pending_acks[protomsg->src] = FALSE;
                --unacked_counts[protomsg->src];
            }

            break;

        case PROTOCOL_CMD_RRQ:
            printf("got RRQ, seq_id: %d, from %d to %d\n", protomsg->seq_id, protomsg->src, protomsg->data1);

            if (protomsg->data2)
            {
                routing_entries[protomsg->data1].seq_id = 0;
            }

            if (protomsg->data1 == TOS_NODE_ID)
            {
                send_rrq_reply(protomsg->seq_id, protomsg->src);
            }

            else if (routing_entries[protomsg->data1].seq_id)
            {
                send_routing_reply(protomsg->seq_id, protomsg->src, protomsg->data1, routing_entries[protomsg->data1].hops + 1);
            }

            else
            {
                send_routing_request_delayed(++own_seq_id, protomsg->data1, protomsg->data2);
            }

            break;

        case PROTOCOL_CMD_RRR:
            printf("got RRR, seq_id: %d, from %d via %d, hops: %d\n", protomsg->seq_id, protomsg->data1, protomsg->src, protomsg->data2);
            if (protomsg->data1 == TOS_NODE_ID)
            {
                break;
            }

            if (pending_rrq && pending_rrq_seq_id == protomsg->seq_id && pending_rrq_dest == protomsg->src)
            {
                pending_rrq = FALSE;
            }

            if (!routing_entries[protomsg->data1].seq_id || routing_entries[protomsg->data1].hops > protomsg->data2)
            {
                routing_entries[protomsg->data1].seq_id = protomsg->seq_id;
                routing_entries[protomsg->data1].next = protomsg->src;
                routing_entries[protomsg->data1].hops = protomsg->data2;
            }

            break;
        }

        printfflush();

        return msg;
    }

    event void Timer.fired()
    {
        if (TOS_NODE_ID == 1)
        {
            if (routing_entries[target].seq_id)
            {
                send_message(++own_seq_id, routing_entries[target].next, PROTOCOL_CMD_LED, target, TOS_NODE_ID);
                if (++target == 5)
                {
                    target = 2;
                }
                call Leds.led2Toggle();
            }

            else
            {
                send_routing_request(++own_seq_id, target, FALSE);
            }
        }
    }

    event void RRQTimer.fired()
    {
        if (pending_rrq)
        {
            pending_rrq = FALSE;
            send_routing_request(pending_rrq_seq_id, pending_rrq_dest, pending_rrq_flush);
        }
    }

    event void ACKTimer.fired()
    {
        int i;
        for (i = 0; i < PROTOCOL_MAX_MOTE_ID; ++i)
        {
            if (pending_acks[i] && ++unacked_counts[i] == 1)
            {
                routing_entries[i].seq_id = 0;
                send_routing_request_delayed(++own_seq_id, i, TRUE);
            }
        }
    }
}

