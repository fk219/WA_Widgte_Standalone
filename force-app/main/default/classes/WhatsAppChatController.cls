@RestResource(urlMapping='/WhatsApp/Incoming/*')
global with sharing class WhatsAppChatController {
    // !!! IMPORTANT: Replace with your actual Twilio credentials and Content SID !!!
    // It's highly recommended to store these in Custom Metadata Types or Protected Custom Settings
    // for better security and easier management, rather than hardcoding them.
    private static final String ACCOUNT_SID = 'YOUR_TWILIO_ACCOUNT_SID'; // Your Twilio Account SID
    private static final String AUTH_TOKEN = 'YOUR_TWILIO_AUTH_TOKEN';    // Your Twilio Auth Token
    private static final String TWILIO_PHONE_NUMBER = '+14155238886'; // Your Twilio WhatsApp-enabled phone number (e.g., +14155238886)
    private static final String ENDPOINT = 'https://api.twilio.com/2010-04-01/Accounts/' + ACCOUNT_SID + '/Messages.json';
    private static final String TEMPLATE_CONTENT_SID = 'HX229f5a04fd0510ce1b071852155d3e75'; // Your Twilio Approved Template SID

    // Custom object and field API names
    // This map allows for easier customization if your field names change
    private static final String OBJECT_API_NAME = 'WhatsAppMessage__c';
    private static final Map<String, String> FIELD_MAP = new Map<String, String>{
        'CONTACT_FIELD' => 'Contact__c',
        'MESSAGE_FIELD' => 'Message__c',
        'DIRECTION_FIELD' => 'Direction__c',
        'TIMESTAMP_FIELD' => 'Timestamp__c',
        'OWNER_FIELD' => 'Owner__c',
        'PHONE_NUMBER_FIELD' => 'Phone_Number__c',
        'MEDIA_URL_FIELD' => 'Media_URL__c',
        'SENT_BY_FIELD' => 'Sent_By__c',
        'TWILIO_SID_FIELD' => 'Twilio_Message_SID__c',
        'STATUS_FIELD' => 'Status__c',
        'IS_READ_FIELD' => 'Is_Read__c'
    };

    @AuraEnabled
    public static void sendTemplateMessage(Id contactId) {
        if (contactId == null) {
            throw new AuraHandledException('Record ID is required.');
        }

        Contact contact = [SELECT Id, Phone FROM Contact WHERE Id = :contactId LIMIT 1];
        if (contact == null || String.isBlank(contact.Phone)) {
            throw new AuraHandledException('Contact not found or phone number is missing.');
        }

        // Ensure the phone number is in E.164 format and includes "whatsapp:" prefix
        String toPhoneNumber = 'whatsapp:' + (contact.Phone.startsWith('+') ? contact.Phone : '+' + contact.Phone);

        // Generate a random 6-digit verification code
        String verificationCode = String.valueOf((Integer)(Math.random() * 900000) + 100000);

        // Twilio API expects Content SID for templates and ContentVariables for placeholders
        Map<String, String> params = new Map<String, String>{
            'From' => 'whatsapp:' + TWILIO_PHONE_NUMBER,
            'To' => toPhoneNumber,
            'ContentSid' => TEMPLATE_CONTENT_SID,
            'ContentVariables' => JSON.serialize(new Map<String, String>{'1' => verificationCode})
        };

        HttpResponse response;
        Savepoint sp = null; // Declare savepoint here

        try {
            response = makeTwilioCallout(params);
            sp = Database.setSavepoint(); // Set savepoint after callout, before DML

            if (response.getStatusCode() == 201) {
                // Parse Twilio response to get message SID or status
                Map<String, Object> responseBody = (Map<String, Object>) JSON.deserializeUntyped(response.getBody());
                String messageSid = (String)responseBody.get('sid');
                String status = (String)responseBody.get('status');

                // Create WhatsAppMessage__c record
                SObject msg = new WhatsAppMessage__c();
                msg.put(FIELD_MAP.get('CONTACT_FIELD'), contact.Id);
                msg.put(FIELD_MAP.get('MESSAGE_FIELD'), verificationCode + ' is your verification code. For your security, do not share this code.'); // Formatted template content
                msg.put(FIELD_MAP.get('DIRECTION_FIELD'), 'Outbound');
                msg.put(FIELD_MAP.get('TIMESTAMP_FIELD'), Datetime.now());
                msg.put(FIELD_MAP.get('OWNER_FIELD'), UserInfo.getUserId());
                msg.put(FIELD_MAP.get('SENT_BY_FIELD'), UserInfo.getUserId());
                msg.put(FIELD_MAP.get('PHONE_NUMBER_FIELD'), contact.Phone); // Storing Contact's Phone
                msg.put(FIELD_MAP.get('TWILIO_SID_FIELD'), messageSid);
                msg.put(FIELD_MAP.get('STATUS_FIELD'), status.capitalize());
                insert msg;

                // Publish Platform Event for real-time updates
                NewWhatsAppMessage__e eventMsg = new NewWhatsAppMessage__e(ContactId__c = contact.Id);
                EventBus.publish(eventMsg);

                System.debug('Template message sent successfully. Twilio SID: ' + messageSid);
            } else {
                throw new AuraHandledException('Twilio API error sending template message: HTTP ' + response.getStatusCode() + ' - ' + response.getBody());
            }
        } catch (CalloutException e) {
            if (sp != null) Database.rollback(sp);
            throw new AuraHandledException('Error sending template message: Callout failed - ' + e.getMessage());
        } catch (Exception e) {
            if (sp != null) Database.rollback(sp);
            System.debug('Error sending template message: ' + e.getMessage() + ' at line ' + e.getLineNumber());
            throw new AuraHandledException('Error sending template message: ' + e.getMessage());
        }
    }

    @AuraEnabled
    public static String normalizePhone(String phoneNumber) {
        if (String.isBlank(phoneNumber)) return '';
        
        // Remove all non-numeric characters
        String normalized = phoneNumber.replaceAll('[^0-9]', '');
        
        // Handle different phone number formats
        if (normalized.length() == 10) {
            // US number without country code
            normalized = '1' + normalized;
        } else if (normalized.length() > 10 && !normalized.startsWith('1')) {
            // International number without US country code
            if (normalized.startsWith('0')) {
                normalized = '1' + normalized.substring(1);
            } else {
                normalized = '1' + normalized;
            }
        }
        
        // Ensure proper E.164 format
        if (!normalized.startsWith('+')) {
            normalized = '+' + normalized;
        }
        
        return normalized;
    }

    @AuraEnabled(cacheable=true)
    public static Map<String, String> getContactDetails(Id contactId) {
        if (contactId == null) {
            throw new AuraHandledException('Contact ID is required.');
        }

        Contact contact = [SELECT Id, FirstName, LastName, Phone FROM Contact WHERE Id = :contactId LIMIT 1];
        if (contact == null) {
            throw new AuraHandledException('Contact not found.');
        }

        return new Map<String, String>{
            'name' => (contact.FirstName != null ? contact.FirstName + ' ' : '') + contact.LastName,
            'phone' => contact.Phone
        };
    }

    @AuraEnabled
    public static Map<String, String> sendWhatsAppMessage(Id contactId, String message, String mediaUrl) {
        if (contactId == null || String.isBlank(message)) {
            throw new AuraHandledException('Record ID and message are required.');
        }

        Contact contact = [SELECT Id, Phone FROM Contact WHERE Id = :contactId LIMIT 1];
        if (contact == null || String.isBlank(contact.Phone)) {
            throw new AuraHandledException('Contact not found or phone number is missing.');
        }

        String toPhoneNumber = 'whatsapp:' + (contact.Phone.startsWith('+') ? contact.Phone : '+' + contact.Phone);

        Map<String, String> params = new Map<String, String>{
            'From' => 'whatsapp:' + TWILIO_PHONE_NUMBER,
            'To' => toPhoneNumber,
            'Body' => message
        };

        if (String.isNotBlank(mediaUrl)) {
            params.put('MediaUrl', mediaUrl);
        }

        HttpResponse response;
        Savepoint sp = null; // Declare savepoint here

        try {
            response = makeTwilioCallout(params);
            System.debug('Twilio API Response Status: ' + response.getStatusCode());
            System.debug('Twilio API Response Body: ' + response.getBody());
            sp = Database.setSavepoint(); // Set savepoint after callout, before DML

            if (response.getStatusCode() == 201) {
                // Parse Twilio response
                Map<String, Object> responseBody = (Map<String, Object>) JSON.deserializeUntyped(response.getBody());
                String messageSid = (String)responseBody.get('sid');
                String status = (String)responseBody.get('status');

                // Create WhatsAppMessage__c record ONLY after successful callout
                WhatsAppMessage__c msg = new WhatsAppMessage__c();
                msg.put(FIELD_MAP.get('CONTACT_FIELD'), contact.Id);
                msg.put(FIELD_MAP.get('MESSAGE_FIELD'), message);
                msg.put(FIELD_MAP.get('DIRECTION_FIELD'), 'Outbound');
                msg.put(FIELD_MAP.get('TIMESTAMP_FIELD'), Datetime.now());
                msg.put(FIELD_MAP.get('OWNER_FIELD'), UserInfo.getUserId());
                msg.put(FIELD_MAP.get('SENT_BY_FIELD'), UserInfo.getName());
                msg.put(FIELD_MAP.get('PHONE_NUMBER_FIELD'), contact.Phone); // Storing Contact's Phone
                if (String.isNotBlank(mediaUrl)) {
                    msg.put(FIELD_MAP.get('MEDIA_URL_FIELD'), mediaUrl);
                }
                // Save Twilio SID and status for status tracking
                msg.put(FIELD_MAP.get('TWILIO_SID_FIELD'), messageSid);
                msg.put(FIELD_MAP.get('STATUS_FIELD'), status != null ? status.capitalize() : 'Sent');
                insert msg;

                // Publish Platform Event for real-time updates
                NewWhatsAppMessage__e eventMsg = new NewWhatsAppMessage__e(ContactId__c = contact.Id);
                EventBus.publish(eventMsg);

                System.debug('WhatsApp message sent successfully. Twilio SID: ' + messageSid);
                return new Map<String, String>{
                    'id' => msg.Id,
                    'status' => status != null ? status.capitalize() : 'Sent'
                };
            } else {
                // Try to parse Twilio error message
                String errorMsg = 'Twilio API error sending WhatsApp message: HTTP ' + response.getStatusCode();
                try {
                    Map<String, Object> errorBody = (Map<String, Object>) JSON.deserializeUntyped(response.getBody());
                    if (errorBody.containsKey('message')) {
                        errorMsg += ' - ' + (String)errorBody.get('message');
                    } else {
                        errorMsg += ' - ' + response.getBody();
                    }
                } catch (Exception parseEx) {
                    errorMsg += ' - ' + response.getBody();
                }
                System.debug('Twilio API ERROR: ' + errorMsg);
                throw new AuraHandledException(errorMsg);
            }
        } catch (CalloutException e) {
            if (sp != null) Database.rollback(sp);
            System.debug('CalloutException: ' + e.getMessage());
            throw new AuraHandledException('Error sending WhatsApp message: Callout failed - ' + e.getMessage());
        } catch (Exception e) {
            if (sp != null) Database.rollback(sp);
            System.debug('Error sending WhatsApp message: ' + e.getMessage() + ' at line ' + e.getLineNumber());
            throw new AuraHandledException('Error sending WhatsApp message: ' + e.getMessage());
        }
    }


    @AuraEnabled(cacheable=true)
    public static List<WhatsAppMessage__c> loadMessages(Id contactId) {
        if (contactId == null) {
            return new List<WhatsAppMessage__c>();
        }
        try {
            // First ensure the contact exists and get their details
            Contact contact = [SELECT Id, Name, Phone FROM Contact WHERE Id = :contactId LIMIT 1];

            // Query for messages with Contact reference
            return [
                SELECT Id, Message__c, Direction__c, Timestamp__c, Media_URL__c,
                       Status__c, Contact__c, Contact__r.Name, Contact__r.Phone,
                       Sent_By__c, Owner__c, Phone_Number__c
                FROM WhatsAppMessage__c 
                WHERE Contact__c = :contactId 
                ORDER BY Timestamp__c ASC
            ];
        } catch (Exception e) {
            System.debug('Error loading messages: ' + e.getMessage());
            throw new AuraHandledException('Error loading messages: ' + e.getMessage());
        }
    }

    // Handles incoming WhatsApp messages from Twilio webhook
    @HttpPost
    global static void handleIncomingMessage() {
        System.debug('=== START handleIncomingMessage ===');
        RestRequest req = RestContext.request;
        RestResponse res = RestContext.response;
        res.addHeader('Content-Type', 'application/xml');
        
        try {
            // Log request details
            System.debug('=== REQUEST DETAILS ===');
            System.debug('Request Method: ' + req.httpMethod);
            System.debug('Request URI: ' + req.requestURI);
            System.debug('Remote Address: ' + req.remoteAddress);
            System.debug('Request Headers: ' + JSON.serialize(req.headers));
            
            // Get and log raw request body
            String requestBody = req.requestBody != null ? req.requestBody.toString() : '';
            System.debug('Raw request body: ' + requestBody);
            
            // Parse parameters
            Map<String, String> params = new Map<String, String>();
            if (req.params != null && !req.params.isEmpty()) {
                params = req.params;
                System.debug('Using URL parameters: ' + JSON.serialize(params));
            } else if (String.isNotBlank(requestBody)) {
                params = parseFormData(requestBody);
                System.debug('Parsed form data: ' + JSON.serialize(params));
            } else {
                System.debug('No parameters found in request');
                res.statusCode = 400;
                res.responseBody = Blob.valueOf('<Response><Message>No parameters found in request</Message></Response>');
                return;
            }
            
            // Check for status callback first
            if (params.containsKey('MessageStatus')) {
                System.debug('Processing status callback');
                handleStatusCallback(params);
                res.statusCode = 200;
                res.responseBody = Blob.valueOf('<Response></Response>');
                return;
            }

            // Process incoming message
            System.debug('=== PROCESSING INCOMING MESSAGE ===');
            String fromWhatsApp = params.get('From');
            String messageBody = params.get('Body');
            String mediaUrl = params.get('MediaUrl0');
            String messageSid = params.get('MessageSid');
            String profileName = params.get('ProfileName');
            
            // Log all parameters for debugging
            System.debug('From: ' + fromWhatsApp);
            System.debug('Message Body: ' + messageBody);
            System.debug('Media URL: ' + mediaUrl);
            System.debug('Message SID: ' + messageSid);
            System.debug('Profile Name: ' + profileName);

            // Validate required fields
            if (String.isBlank(fromWhatsApp) || (String.isBlank(messageBody) && String.isBlank(mediaUrl))) {
                String errorMsg = 'Missing required parameters. From: ' + fromWhatsApp + ', Body: ' + messageBody;
                System.debug('VALIDATION ERROR: ' + errorMsg);
                res.statusCode = 400;
                res.responseBody = Blob.valueOf('<Response><Message>' + errorMsg + '</Message></Response>');
                return;
            }

            try {
                // Check if message already exists to prevent duplicates
                if (String.isNotBlank(messageSid)) {
                    List<WhatsAppMessage__c> existingMessages = [
                        SELECT Id FROM WhatsAppMessage__c 
                        WHERE Twilio_Message_SID__c = :messageSid 
                        LIMIT 1
                    ];
                    
                    if (!existingMessages.isEmpty()) {
                        System.debug('Message already exists with SID: ' + messageSid);
                        res.statusCode = 200;
                        res.responseBody = Blob.valueOf('<Response><Message>Duplicate message received</Message></Response>');
                        return;
                    }
                }

                // Normalize phone number (strip non-digits, add '+')
                String rawPhone = fromWhatsApp.replace('whatsapp:', '');
                String normalizedPhone = '+' + rawPhone.replaceAll('\\D', '');
                Id contactId = null;
                try {
                    List<Contact> contacts = [SELECT Id FROM Contact WHERE Phone = :normalizedPhone LIMIT 1];
                    if (!contacts.isEmpty()) {
                        contactId = contacts[0].Id;
                    } else {
                        System.debug('No Contact found for inbound WhatsApp message. Phone: ' + normalizedPhone);
                    }
                } catch (Exception lookupEx) {
                    System.debug('Error during Contact lookup for inbound WhatsApp message. Phone: ' + normalizedPhone + ' Error: ' + lookupEx.getMessage());
                }

                // Create message record
                WhatsAppMessage__c msg = new WhatsAppMessage__c(
                    Message__c = String.isNotBlank(messageBody) ? messageBody : '(Media Message)',
                    Direction__c = 'Inbound',
                    Timestamp__c = Datetime.now(),
                    OwnerId = UserInfo.getUserId(),
                    Sent_By__c = 'Customer',
                    Phone_Number__c = rawPhone,
                    Twilio_Message_SID__c = messageSid,
                    Status__c = 'Delivered',
                    Media_URL__c = mediaUrl,
                    Contact__c = contactId
                );
                
                System.debug('Attempting to save message: ' + JSON.serialize(msg));
                
                // Insert message with error handling
                Database.SaveResult sr = Database.insert(msg, false);
                if (sr.isSuccess()) {
                    System.debug('Message saved successfully with ID: ' + msg.Id);
                    res.statusCode = 200;
                    res.responseBody = Blob.valueOf('<Response></Response>');
                } else {
                    String errorMsg = 'Failed to save message: ';
                    for(Database.Error err : sr.getErrors()) {
                        errorMsg += err.getStatusCode() + ': ' + err.getMessage() + '; ';
                    }
                    System.debug('DATABASE ERROR: ' + errorMsg);
                    res.statusCode = 500;
                    res.responseBody = Blob.valueOf('<Response><Message>Error saving message: ' + errorMsg + '</Message></Response>');
                }
                
            } catch(DmlException e) {
                System.debug('DML EXCEPTION: ' + e.getMessage() + '\n' + e.getStackTraceString());
                res.statusCode = 500;
                res.responseBody = Blob.valueOf('<Response><Message>Database error: ' + e.getMessage() + '</Message></Response>');
            }

        } catch (Exception e) {
            System.debug('UNEXPECTED ERROR: ' + e.getMessage() + '\n' + e.getStackTraceString());
            res.statusCode = 500;
            res.responseBody = Blob.valueOf('<Response><Message>Error processing message: ' + e.getMessage() + '</Message></Response>');
        } finally {
            System.debug('=== END handleIncomingMessage ===');
        }
    }
    
    // Handle status callbacks separately for better organization
    private static void handleStatusCallback(Map<String, String> params) {
        String messageSid = params.get('MessageSid');
        String newStatus = params.get('MessageStatus');
        
        if (String.isBlank(messageSid) || String.isBlank(newStatus)) {
            System.debug('Invalid status callback payload: ' + JSON.serialize(params));
            return;
        }
        
        try {
            // Update message status and handle read receipts
            List<WhatsAppMessage__c> messages = [
                SELECT Id, Status__c, Is_Read__c, Contact__c
                FROM WhatsAppMessage__c
                WHERE Twilio_Message_SID__c = :messageSid
                LIMIT 1
            ];

            if (!messages.isEmpty()) {
                WhatsAppMessage__c msg = messages[0];
                msg.Status__c = newStatus.capitalize();
                Boolean statusChanged = true;
                Boolean readChanged = false;

                // If status is 'read', set Is_Read__c = true
                if (newStatus != null && newStatus.toLowerCase() == 'read') {
                    if (msg.Is_Read__c != true) {
                        msg.Is_Read__c = true;
                        readChanged = true;
                    }
                }
                update msg;
                System.debug('Updated message status: ' + messageSid + ' -> ' + newStatus + (readChanged ? ' (marked as read)' : ''));

                // Publish Platform Event for real-time updates if status or read changed
                try {
                    NewWhatsAppMessage__e eventMsg = new NewWhatsAppMessage__e(ContactId__c = msg.Contact__c);
                    EventBus.publish(eventMsg);
                } catch (Exception eventEx) {
                    System.debug('Error publishing platform event: ' + eventEx.getMessage());
                }
            } else {
                System.debug('Message not found for SID: ' + messageSid);
            }
        } catch(Exception e) {
            System.debug('Error updating message status: ' + e.getMessage() + '\n' + e.getStackTraceString());
        }
    }

    // Helper method to parse form data from request body
    private static Map<String, String> parseFormData(String formData) {
        Map<String, String> params = new Map<String, String>();
        if (String.isBlank(formData)) return params;
        
        for (String pair : formData.split('&')) {
            List<String> keyValue = pair.split('=', 2);
            if (keyValue.size() == 2) {
                params.put(
                    EncodingUtil.urlDecode(keyValue[0], 'UTF-8'),
                    EncodingUtil.urlDecode(keyValue[1], 'UTF-8')
                );
            }
        }
        return params;
    }

    // Helper method to make Twilio API callout
    private static HttpResponse makeTwilioCallout(Map<String, String> params) {
        HttpRequest req = new HttpRequest();
        req.setMethod('POST');
        req.setEndpoint(ENDPOINT);
        req.setHeader('Authorization', 'Basic ' + EncodingUtil.base64Encode(Blob.valueOf(ACCOUNT_SID + ':' + AUTH_TOKEN)));
        req.setHeader('Content-Type', 'application/x-www-form-urlencoded');

        String body = '';
        for (String key : params.keySet()) {
            if (String.isNotBlank(body)) {
                body += '&';
            }
            body += EncodingUtil.urlEncode(key, 'UTF-8') + '=' + EncodingUtil.urlEncode(params.get(key), 'UTF-8');
        }
        req.setBody(body);

        Http http = new Http();
        return http.send(req);
    }

}