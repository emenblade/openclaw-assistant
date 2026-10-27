# Importance Rules

Edit these rules freely. The triage agent reads this file before classifying mail.

## VIP

```text
# Exact addresses
- alice@example.com
- school@example.org

# Domains
- mybank.com
- myairline.com
```

## Always notify immediately

- Invoice, contract, deadline, “action required”
- Flight changes, cancellations, appointments
- School closures, medical results
- Security alerts
- Anything from VIP senders
- Calendar invites from known senders

## Digest only

- Receipts under $100
- GitHub notifications
- Newsletters the owner actually reads
- Package delivery updates
- Non-urgent FYI threads

## Ignore

- Marketing
- Cold outreach
- Social notifications
- Newsletters the owner never reads
- Spam

## Calendar

- Write only to the Assistant calendar
- Auto-create only explicit invites/confirmations with date + time
- Check the main calendar for conflicts
- If confidence < 0.8, ask
- Accept/decline invites only with approval
- Invite attendees only with approval
- Include source Message-ID in the event description
- Deduplicate by Message-ID and event hash

## Quiet hours

- 22:00–07:00 owner timezone
- Urgent/VIP may bypass
- Non-urgent waits for the digest

## Feedback history

Add dated notes when the owner corrects the assistant.

```text
2026-10-26: Initial rules.
```
