# Terms of Service — Lancer

**Last updated:** {{DATE}}

---

## 1. Acceptance

By downloading, installing, or using Lancer (the "App"), you agree to be bound
by these Terms of Service (the "Terms"). If you do not agree, do not use the
App.

The App is published by **[Legal entity name — placeholder: insert company or
individual name]**.

These Terms supplement the Apple App Store Terms of Service (the "Apple
Terms"). To the extent of any conflict, these Terms govern your use of the
App.

---

## 2. The App's purpose

Lancer is an iOS approval-firewall and audit interface for AI coding agents
(Claude Code, Codex, opencode) that run on computers you own or control. The
App:

- Connects to your remote host via SSH
- Shows you approval requests from agents running on that host
- Lets you approve, deny, or edit proposed actions
- Displays a running transcript of agent activity

**The App does not execute, compile, download, or install code on your iOS
device.** All code execution occurs on your remote host.

---

## 3. License

Lancer grants you a personal, non-transferable, non-exclusive license to use
the App on Apple-branded devices that you own or control, as permitted by the
Apple Terms.

---

## 4. Your responsibilities

### 4.1 Authorized access only

You may use Lancer only to connect to:

- Hosts that you own
- Hosts that you are explicitly authorized by the owner to access

You are solely responsible for maintaining the security of your SSH keys and
host credentials.

### 4.2 Your agents, your liability

You control what AI coding agents do on your host. Lancer merely relays
approval decisions. You are responsible for:

- The actions your agents perform
- Compliance with any laws or policies applicable to your code and data
- Ensuring your agents do not introduce vulnerabilities, violate licenses, or
  expose sensitive information

### 4.3 Prohibited uses

You must not use Lancer to:

- Access any system without authorization
- Distribute malware, ransomware, or other harmful code
- Conduct denial-of-service attacks or network abuse
- Violate applicable export control or sanctions laws
- Circumvent any technical or legal restriction on the host system

---

## 5. Accounts

**Lancer does not create or manage user accounts.** Pairing is
device-to-device — you scan a QR code from your host to link your phone.
There is no login, no profile, and no Lancer-hosted user database.

If you purchase Founder's Edition via in-app purchase, Apple manages the
transaction and receipt. Lancer does not create a separate account for this
purpose.

---

## 6. In-app purchases and Pro tier

### 6.1 Current offering (GA)

**Founder's Edition** is a limited-time, one-time in-app purchase (non-consumable) for
early adopters. Price is displayed in the App at **$89.99** (one-time, within the $79–99
band). Founder's Edition unlocks convenience surfaces (e.g., multi-host management,
advanced surfaces) and is **grandfathered into the future Pro subscription**. The core trust
loop — approval inbox, policy, audit, emergency stop — is **free** and will not be paywalled.
Apple processes all payments.

**Lancer Cloud** (hosted execution billed via Stripe) is **not offered at GA** — backend
code exists for V2 but no checkout is exposed in the shipping app.

### 6.2 Future subscription (post-G5 — not yet available)

After retention proof (SHIP_PLAN G5), a standard Pro subscription (~$8–12/mo or ~$79/yr)
is planned for multi-machine / unlimited runs / multi-device sync. Founder's Edition buyers
are grandfathered. When and if it ships, the following will apply:

- Auto-renewing subscription managed by Apple's StoreKit 2
- Pricing and duration displayed before purchase
- Subscriptions renew unless cancelled at least 24 hours before the period
  ends
- Manage / cancel via Apple's Subscription settings on your device
- Refunds handled by Apple per their policy

### 6.3 General IAP terms

- All purchases are final unless Apple's refund policy applies
- Prices are as displayed in the App and may be updated for future purchases
- Founder's Edition is a single-device purchase (Apple ID bound)

---

## 7. Third-party services

The App interacts with the following third-party services that you configure:

| Service | Role | Provider terms |
|---------|------|----------------|
| Your SSH host (your own machine) | Runs your agents | Your own responsibility |
| Apple Push Notification service | Delivers notifications | Apple Developer Program License Agreement |
| Fly.io | Hosts the push relay | Fly.io Terms of Service |
| Stripe (if applicable) | Payment processing for conduit.dev subscriptions | Stripe Services Agreement |

Lancer is not responsible for the availability, security, or policies of
these third-party services.

---

## 8. Disclaimer of warranties

**THE APP IS PROVIDED "AS IS" AND "AS AVAILABLE," WITHOUT WARRANTY OF ANY
KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE, AND NON-INFRINGEMENT.**

Lancer does not warrant that:

- The App will be uninterrupted, timely, secure, or error-free
- The results obtained from the App will be accurate or reliable
- Any errors in the App will be corrected

**Security tool disclaimer.** Lancer is a tool to assist with agent
governance. It does not guarantee that your agents will never perform
unauthorized or harmful actions. You must independently verify agent behavior
and maintain backups.

---

## 9. Limitation of liability

TO THE MAXIMUM EXTENT PERMITTED BY APPLICABLE LAW, IN NO EVENT SHALL
**[Legal entity name]** BE LIABLE FOR ANY INDIRECT, INCIDENTAL, SPECIAL,
CONSEQUENTIAL, OR EXEMPLARY DAMAGES, INCLUDING BUT NOT LIMITED TO DAMAGES FOR
LOSS OF PROFITS, GOODWILL, USE, DATA, OR OTHER INTANGIBLE LOSSES, ARISING OUT
OF OR IN CONNECTION WITH THE USE OR INABILITY TO USE THE APP.

Our total liability to you shall not exceed the greater of (a) the amount you
paid for the App (including any in-app purchases) in the twelve (12) months
preceding the claim, or (b) one hundred U.S. dollars ($100.00).

---

## 10. Apple's standard EULA

Apple's Licensed Application End User License Agreement (the "Apple EULA")
applies to your use of the App as downloaded from the App Store. These Terms
do not limit any rights you have under the Apple EULA.

---

## 11. Termination

We may terminate or suspend your access to the App at any time, without prior
notice, for conduct that we believe violates these Terms or is harmful to
other users, us, or third parties.

Upon termination:
- Your license to use the App ends
- You must cease all use and delete the App
- Local data on your device will be removed when you delete the App

---

## 12. Changes to these Terms

We may update these Terms from time to time. Material changes will be
notified through the App. Your continued use after the effective date
constitutes acceptance of the updated Terms.

---

## 13. Governing law

These Terms are governed by the laws of **[Jurisdiction — placeholder:
e.g., the State of California, USA]**, without regard to its conflict-of-law
provisions. The exclusive venue for any dispute shall be the state and federal
courts in **[County / District — placeholder]**.

---

## 14. Contact

| Role | Contact |
|------|---------|
| General / legal inquiries | **[legal@conduit.dev — placeholder]** |
| Support | **[support@conduit.dev — placeholder]** |
| DMCA / takedown notices | **[legal@conduit.dev — placeholder]** |

---

## Sources

- Apple App Store Review Guidelines §3.1.1 (IAP), §4.2 (Functionality), §5.1:
  <https://developer.apple.com/app-store/review/guidelines/>
- Apple Licensed Application End User License Agreement:
  <https://www.apple.com/legal/internet-services/itunes/dev/stdeula/>
- Apple SDK minimum requirements (April 28, 2026):
  <https://developer.apple.com/news/upcoming-requirements/?id=02032026a>
