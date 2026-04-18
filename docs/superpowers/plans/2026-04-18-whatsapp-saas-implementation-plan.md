# WhatsApp SaaS Integration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Transform the standalone Twilio WhatsApp integration into a multi-tenant SaaS application that supports both Meta and Twilio APIs, dynamic object mapping, strict license enforcement, real-time multimedia, and Omni-Channel routing.

**Architecture:** The project is split into several major subsystems:
1.  **Core Data Model:** Replacing hardcoded Lookups with polymorphic IDs and setting up Protected Custom Settings/Metadata for configuration.
2.  **API Integration Layer:** Refactoring the Apex Controller to handle dynamic configurations (Meta vs Twilio) and generic webhook processing.
3.  **LWC Chat Widget Refactor:** Updating the UI to handle dynamic record IDs, the 24-hour compliance rule, and multimedia rendering.
4.  **Omni-Channel & Notifications:** Building the Global Utility Bar component, Custom Notifications, and Omni-Channel `PendingServiceRouting` logic.
5.  **Admin Setup Wizard:** Creating the LWC application for Admins to manage mappings, APIs, and templates.

**Tech Stack:** Salesforce Apex, Lightning Web Components (LWC), Platform Events, Salesforce REST API, Omni-Channel.

---

### Task 1: Core Data Model & Configuration Objects

**Goal:** Create the foundation for storing configuration securely and making the `WhatsAppMessage__c` object polymorphic.

**Files:**
- Create: `force-app/main/default/objects/WhatsApp_Setting__mdt/WhatsApp_Setting__mdt.object-meta.xml` (and fields)
- Create: `force-app/main/default/objects/App_License_Status__c/App_License_Status__c.object-meta.xml` (Custom Setting)
- Modify: `force-app/main/default/objects/WhatsAppMessage__c/...` (Delete `Contact__c`, Add `Parent_Record_Id__c`, `Parent_Object_Type__c`)

- [ ] **Step 1: Create App License Custom Setting**
Create a Protected Hierarchy Custom Setting `App_License_Status__c` with a text field `Status__c` to hold the 'LOCKED' or 'ACTIVE' state.

- [ ] **Step 2: Create WhatsApp Settings Custom Metadata Type**
Create a Protected Custom Metadata Type `WhatsApp_Setting__mdt` with fields:
`API_Provider__c` (Picklist: Meta, Twilio), `API_Key__c` (Text 255), `Auth_Token__c` (Text 255), `Phone_Number_ID__c` (Text 255).

- [ ] **Step 3: Update WhatsAppMessage__c Object**
Modify the custom object. Remove the hardcoded `Contact__c` Master-Detail field. Add:
`Parent_Record_Id__c` (Text 18)
`Parent_Object_Type__c` (Text 255)
Make the object's OWD (Organization-Wide Defaults) Private.

- [ ] **Step 4: Create Field Mapping Custom Metadata Type**
Create `WhatsApp_Object_Mapping__mdt` with fields:
`Object_API_Name__c` (Text 255), `Primary_Phone_Field__c` (Text 255), `Country_Code_Field__c` (Text 255).

- [ ] **Step 5: Commit Data Model Changes**
```bash
git add force-app/main/default/objects/
git commit -m "feat: setup core data model and custom metadata for SaaS config"
```

### Task 2: Apex License Enforcement & Dynamic Config

**Goal:** Build the Apex utility class that checks licenses and reads the dynamic configuration.

**Files:**
- Create: `force-app/main/default/classes/WhatsAppConfigUtil.cls`
- Create: `force-app/main/default/classes/WhatsAppConfigUtilTest.cls`

- [ ] **Step 1: Write tests for Config Util**
Create tests expecting `checkLicenseStatus` to throw an exception if locked, and tests to verify dynamic metadata retrieval.

- [ ] **Step 2: Implement WhatsAppConfigUtil.cls**
Implement `checkLicenseStatus()` which reads `App_License_Status__c`. If 'LOCKED', throw an `AuraHandledException`. Also check `UserInfo.isCurrentUserLicensed('namespace')` (mock this for testing).
Implement `getApiSettings()` to query `WhatsApp_Setting__mdt`.
Implement `getObjectMapping(String objectName)` to query `WhatsApp_Object_Mapping__mdt`.

- [ ] **Step 3: Run Tests**
```bash
sfdx force:apex:test:run -n WhatsAppConfigUtilTest -c
```
Expected: PASS

- [ ] **Step 4: Commit Apex Utility**
```bash
git add force-app/main/default/classes/WhatsAppConfigUtil*
git commit -m "feat: implement license checking and dynamic config utilities"
```

### Task 3: Refactor Webhook Listener for Omni-Channel

**Goal:** Update the `@RestResource` to handle generic objects, check owner licensing, and push to Omni-Channel if unassigned/unlicensed.

**Files:**
- Modify: `force-app/main/default/classes/WhatsAppChatController.cls`

- [ ] **Step 1: Refactor `handleIncomingMessage`**
Instead of looking up just Contacts, dynamically query the objects defined in `WhatsApp_Object_Mapping__mdt` based on the incoming phone number.

- [ ] **Step 2: Implement Owner License Check**
Once a matching record is found (e.g., Lead), check if the `OwnerId` is an active, licensed user.

- [ ] **Step 3: Implement Omni-Channel Fallback**
If the owner is not licensed, create a `PendingServiceRouting` record pointing to a pre-defined Service Channel / Queue, rather than just saving the message silently.

- [ ] **Step 4: Update Message Insertion**
Save the `WhatsAppMessage__c` using `Parent_Record_Id__c` instead of `Contact__c`.

- [ ] **Step 5: Commit Webhook Changes**
```bash
git add force-app/main/default/classes/WhatsAppChatController.cls
git commit -m "feat: refactor webhook for polymorphic linking and omni-channel routing"
```

### Task 4: Global Notification LWC (Utility Bar)

**Goal:** Build a Utility Bar component that listens to Platform Events and alerts the user of incoming messages.

**Files:**
- Create: `force-app/main/default/lwc/whatsappGlobalNotification/...`

- [ ] **Step 1: Scaffold LWC**
Create the JS, HTML, and XML files for `whatsappGlobalNotification`. Configure the XML target to `lightning__UtilityBar`.

- [ ] **Step 2: Implement `empApi` Subscription**
In `connectedCallback`, subscribe to the `NewWhatsAppMessage__e` platform event.

- [ ] **Step 3: Implement Notification Logic**
When an event fires, check if the `OwnerId` of the parent record matches the current User. If yes, increment a local `@track unreadCount` and use the `lightning/platformUtilityBarApi` to set the utility icon badge (`setUtilityIcon` and `setUtilityHighlighted`).

- [ ] **Step 4: Implement Navigation**
When the user clicks the utility bar item, display a list of recent notifications. Clicking a notification uses `lightning/navigation` to navigate to the specific `Parent_Record_Id__c`.

- [ ] **Step 5: Commit Utility Bar**
```bash
git add force-app/main/default/lwc/whatsappGlobalNotification/
git commit -m "feat: implement global utility bar notification component"
```

### Task 5: Chat Widget Refactor (Dynamic UI & 24hr Window)

**Goal:** Update the existing Chat Widget to use the new polymorphic data model and enforce the 24-hour rule.

**Files:**
- Modify: `force-app/main/default/lwc/whatsappChatWidget/...`

- [ ] **Step 1: Refactor for Dynamic Records**
Change the component to accept `@api recordId` and `@api objectApiName`. Update the Apex calls to pass `objectApiName` so the backend knows which mapping to use.

- [ ] **Step 2: Implement 24-Hour Timer Logic**
Add a getter `get is24HourWindowOpen()`. Calculate the difference between `lastMessageTimestamp` (if Inbound) and `Date.now()`.

- [ ] **Step 3: Update UI for Auto-Lock**
If `is24HourWindowOpen` is false, disable the text `<textarea>` and the media upload button. Display a warning message: "24-hour window closed. Please use a template." Show a button to open a Template selection modal.

- [ ] **Step 4: Commit Widget Refactor**
```bash
git add force-app/main/default/lwc/whatsappChatWidget/
git commit -m "feat: refactor chat widget for dynamic objects and 24-hour compliance"
```