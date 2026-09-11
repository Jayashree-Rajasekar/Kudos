import { LightningElement, wire } from "lwc";
import { refreshApex } from "@salesforce/apex";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import giveKudo from "@salesforce/apex/KudosService.giveKudo";
import getRecentKudos from "@salesforce/apex/KudosService.getRecentKudos";
import getActiveBadgeTypes from "@salesforce/apex/KudosService.getActiveBadgeTypes";

export default class KudosWall extends LightningElement {
  recipientId;
  badgeTypeId;
  message = "";
  isSubmitting = false;

  wiredKudosResult;
  kudos = [];
  badgeOptions = [];

  @wire(getRecentKudos, { numberOfRecords: 20 })
  wiredKudos(result) {
    this.wiredKudosResult = result;
    if (result.data) {
      this.kudos = result.data.map((item) => ({
        id: item.id,
        message: item.message,
        recipientName: item.recipientName,
        giverName: item.giverName,
        badgeName: item.badgeName,
        tierLabel: item.tierLabel,
        tierIcon: item.tierIcon,
        giverInitials: this.getInitials(item.giverName)
      }));
    } else if (result.error) {
      this.showToast("Error", this.reduceError(result.error), "error");
    }
  }

  @wire(getActiveBadgeTypes)
  wiredBadgeTypes({ data, error }) {
    if (data) {
      this.badgeOptions = data.map((bt) => ({ label: bt.Name, value: bt.Id }));
    } else if (error) {
      this.showToast("Error", this.reduceError(error), "error");
    }
  }

  get hasNoKudos() {
    return !this.kudos || this.kudos.length === 0;
  }

  get isSubmitDisabled() {
    return (
      this.isSubmitting ||
      !this.recipientId ||
      !this.badgeTypeId ||
      !this.message
    );
  }

  handleRecipientChange(event) {
    this.recipientId = event.detail.recordId;
  }

  handleBadgeChange(event) {
    this.badgeTypeId = event.detail.value;
  }

  handleMessageChange(event) {
    this.message = event.detail.value;
  }

  async handleSubmit() {
    this.isSubmitting = true;
    try {
      await giveKudo({
        recipientId: this.recipientId,
        badgeTypeId: this.badgeTypeId,
        message: this.message
      });
      this.showToast("Success", "Kudo sent!", "success");
      this.message = "";
      this.badgeTypeId = undefined;
      this.recipientId = undefined;
      await refreshApex(this.wiredKudosResult);
    } catch (error) {
      this.showToast("Error", this.reduceError(error), "error");
    } finally {
      this.isSubmitting = false;
    }
  }

  getInitials(name) {
    if (!name) {
      return "";
    }
    return name
      .trim()
      .split(/\s+/)
      .slice(0, 2)
      .map((part) => part.charAt(0).toUpperCase())
      .join("");
  }

  showToast(title, message, variant) {
    this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
  }

  reduceError(error) {
    if (error && error.body && error.body.message) {
      return error.body.message;
    }
    return "An unexpected error occurred.";
  }
}
