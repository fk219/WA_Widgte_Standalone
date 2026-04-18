import { LightningElement, track } from 'lwc';

export default class WhatsappAdminDashboard extends LightningElement {
    @track selectedProvider = 'Twilio';
    
    get providerOptions() {
        return [
            { label: 'Twilio API', value: 'Twilio' },
            { label: 'Meta Official Cloud API', value: 'Meta' }
        ];
    }

    get isTwilio() {
        return this.selectedProvider === 'Twilio';
    }

    get isMeta() {
        return this.selectedProvider === 'Meta';
    }

    handleProviderChange(event) {
        this.selectedProvider = event.detail.value;
    }

    saveSettings() {
        // In a real app, this would call an Apex method that uses the Metadata.Operations class
        // to enqueue a deployment to save the Custom Metadata Type records.
        alert('Settings saved successfully (Mock)');
    }
}
