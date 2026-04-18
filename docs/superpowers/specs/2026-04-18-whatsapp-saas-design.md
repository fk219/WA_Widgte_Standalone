# WhatsApp Integration SaaS Design Specification

## Overview
This specification details the transformation of a single-org Salesforce WhatsApp integration into a commercial, multi-tenant SaaS application (AppExchange Managed Package). The application allows users to connect either the Official WhatsApp Cloud API (Meta) or Twilio, providing a rich, real-time messaging interface directly within Salesforce records.

## 1. Security & Monetization (License Enforcement)
*   **AppExchange LMA:** The package will be distributed using the License Management Application (LMA). Salesforce physically restricts access so that if a client pays for 2 licenses, only 2 users can be assigned the package license.
*   **Hub Telemetry:** A scheduled Apex job will securely ping a central external Hub (owned by the ISV) daily with usage statistics (message volume, active users).
*   **Heartbeat Lock:** If the Hub indicates an unpaid status, a Protected Custom Setting (`App_Status__c`) is flipped to `LOCKED`. The LWC widget will check this setting on initialization and display a hard block ("Subscription Expired") if locked.

## 2. Admin Configuration App (Setup Wizard)
A dedicated Lightning App available only to System Administrators for configuring the package.

### 2.1 Provider Configuration
*   **API Selection:** Toggle between [Official WhatsApp Cloud API] and [Twilio].
*   **Credential Storage:** Securely store Meta App ID/Token or Twilio SID/Token in Protected Custom Metadata Types.
*   **Visibility Settings:** Toggle to show/hide the connected business phone number in the widget UI.

### 2.2 Object & Field Mapping
*   **Dynamic Object Selection:** Admin selects which objects the widget can be placed on (e.g., Lead, Contact, Account, Custom Objects).
*   **Phone Field Mapping:** For each selected object, the Admin can map multiple phone fields (e.g., `Phone`, `MobilePhone`, `WhatsApp_Number__c`).
*   **Country Code Mapping:** Optional configuration to map a separate field that holds the country code, which the Apex controller will concatenate with the phone number at runtime.

### 2.3 Template Management
*   **Template Syncing:** A UI to fetch and display approved templates directly from the Meta/Twilio API.
*   **Template Creation:** A form to create new templates (with variables) and submit them to Meta for approval directly from Salesforce.
*   **Template Status:** Display approval status (Approved, Pending, Rejected) for each template.

## 3. The Chat Widget (LWC)

### 3.1 UI/UX & Responsiveness
*   **Form Factor:** The widget will be built as a responsive LWC, compatible with desktop (record page sidebar), tablets, and the Salesforce Mobile App.
*   **Number Selection:** If the Admin mapped multiple phone fields (e.g., Mobile, Alternate, WhatsApp), the widget will display a dropdown allowing the user to select which number to send the message to.
*   **Message Metadata:** Each message bubble will clearly stamp:
    *   The sender's name (which Salesforce user sent it, or if it was inbound).
    *   Timestamp.
    *   Delivery Status (Sent, Delivered, Read) with native WhatsApp-style checkmarks.
    *   Date/Time separator lines (e.g., "TODAY", "YESTERDAY").

### 3.2 Real-Time Communication
*   **Platform Events:** Utilizes `empApi` to subscribe to a custom Platform Event (`NewWhatsAppMessage__e`).
*   **Inbound Webhooks:** A secure `@RestResource` endpoint receives webhooks from Meta/Twilio and publishes the Platform Event, ensuring the chat UI updates instantly without a page refresh.

### 3.3 Rich Media Support
*   **Sending Media:** Users can upload images, PDFs, short audio, and short video files. The LWC will pass these to Apex, which will upload them to Salesforce Files (ContentVersion) and generate a public URL to pass to the WhatsApp API.
*   **Receiving Media:** Inbound webhooks containing media URLs will be processed. The LWC will use standard HTML5 tags (`<audio>`, `<video>`, `<img>`, `<embed>`) to stream and display the media directly in the chat history.

## 4. Data Architecture & Storage

*   **WhatsApp_Message__c (Custom Object):**
    *   Stores individual messages.
    *   **Polymorphic Linking:** Uses `Parent_Record_Id__c` (Text/18) instead of a hardcoded lookup, allowing messages to link to *any* Salesforce object dynamically.
    *   Stores direction, status, timestamps, media URLs, and the sender's User lookup.
*   **Accessibility:** Because messages are stored in a standard Custom Object, Salesforce Admins can easily build standard Salesforce Reports and Dashboards to audit chat history, agent response times, and message volume.

## 5. Brainstorming: Missing Features & Considerations

*   **Opt-Out / Consent Management:** Critical for compliance (GDPR/TCPA). We need a mechanism to flag a record as "Do Not WhatsApp" and physically block the widget from sending outbound messages to that number.
*   **24-Hour Customer Service Window:** WhatsApp enforces a strict 24-hour rule. If a customer hasn't replied in 24 hours, the agent *must* use a pre-approved Template. The widget needs logic to calculate this window and restrict the text input box, forcing the user to select a template if the window is closed.
*   **File Storage Limits:** Media files take up significant Salesforce file storage space. Consider a feature in the Admin Setup to automatically purge media older than X months to save costs for the client.
*   **Concurrent Webhook Limits:** High volumes of incoming messages could hit Apex concurrent execution limits. The webhook should immediately insert a raw staging record and use an asynchronous Platform Event Trigger to process the actual logic and media downloading.