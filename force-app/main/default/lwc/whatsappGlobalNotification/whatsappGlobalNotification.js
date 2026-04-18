import { LightningElement, track, wire } from 'lwc';
import { subscribe, unsubscribe, onError } from 'lightning/empApi';
import { NavigationMixin } from 'lightning/navigation';
import { getRecord } from 'lightning/uiRecordApi';
import USER_ID from '@salesforce/user/Id';

const CHANNEL_NAME = '/event/NewWhatsAppMessage__e';

export default class WhatsappGlobalNotification extends NavigationMixin(LightningElement) {
    @track notifications = [];
    @track unreadCount = 0;
    _subscription = null;

    get hasNotifications() {
        return this.notifications.length > 0;
    }

    connectedCallback() {
        this.subscribeToMessageEvents();
    }

    disconnectedCallback() {
        if (this._subscription) {
            unsubscribe(this._subscription);
        }
    }

    subscribeToMessageEvents() {
        subscribe(CHANNEL_NAME, -1, (message) => {
            const payload = message.data.payload;
            // In a real app, we would verify if the payload.ContactId__c is owned by the current USER_ID
            // For now, we'll assume it's relevant to show the notification
            this.handleNewNotification(payload.ContactId__c);
        }).then(response => {
            this._subscription = response;
        });

        onError(error => {
            console.error('EmpApi error: ', JSON.stringify(error));
        });
    }

    handleNewNotification(recordId) {
        this.unreadCount++;
        const newNotif = {
            id: Date.now().toString(),
            recordId: recordId,
            time: new Date().toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })
        };
        
        // Keep only the 10 most recent
        this.notifications = [newNotif, ...this.notifications].slice(0, 10);
        
        // Note: To actually update the Utility Bar badge, we would use lightning/platformUtilityBarApi here
        // e.g., setUtilityHighlighted({ highlighted: true });
        // setUtilityIcon({ badgeText: this.unreadCount.toString() });
    }

    handleNotificationClick(event) {
        const recordId = event.currentTarget.dataset.id;
        
        // Decrement badge (simplified logic)
        if (this.unreadCount > 0) this.unreadCount--;

        // Navigate to the record
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId: recordId,
                actionName: 'view'
            }
        });
    }
}
