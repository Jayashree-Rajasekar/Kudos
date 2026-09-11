import { createElement } from "lwc";
import { registerApexTestWireAdapter } from "@salesforce/sfdx-lwc-jest";
import KudosWall from "c/kudosWall";
import getRecentKudos from "@salesforce/apex/KudosService.getRecentKudos";
import getActiveBadgeTypes from "@salesforce/apex/KudosService.getActiveBadgeTypes";
import giveKudo from "@salesforce/apex/KudosService.giveKudo";

jest.mock(
  "@salesforce/apex/KudosService.giveKudo",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

const getRecentKudosAdapter = registerApexTestWireAdapter(getRecentKudos);
const getActiveBadgeTypesAdapter =
  registerApexTestWireAdapter(getActiveBadgeTypes);

const MOCK_KUDOS = [
  {
    Id: "a01000000000001",
    Message__c: "Great job on the release!",
    Recipient__r: { Name: "Jamie Recipient" },
    Giver__r: { Name: "Alex Giver" },
    Badge_Type__r: { Name: "Team Player", Icon_Name__c: "utility:groups" }
  }
];

const MOCK_BADGE_TYPES = [
  {
    Id: "a02000000000001",
    Name: "Team Player",
    Icon_Name__c: "utility:groups",
    Points_Value__c: 10
  }
];

describe("c-kudos-wall", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it("renders the recent kudos returned by the wire adapter", () => {
    const element = createElement("c-kudos-wall", { is: KudosWall });
    document.body.appendChild(element);

    getRecentKudosAdapter.emit(MOCK_KUDOS);

    return Promise.resolve().then(() => {
      const items = element.shadowRoot.querySelectorAll("li.slds-box");
      expect(items.length).toBe(1);
      expect(items[0].textContent).toContain("Great job on the release!");
    });
  });

  it("shows an empty-state message when there are no kudos yet", () => {
    const element = createElement("c-kudos-wall", { is: KudosWall });
    document.body.appendChild(element);

    getRecentKudosAdapter.emit([]);

    return Promise.resolve().then(() => {
      expect(element.shadowRoot.textContent).toContain("No kudos yet");
    });
  });

  it("populates badge type options from the wire adapter", () => {
    const element = createElement("c-kudos-wall", { is: KudosWall });
    document.body.appendChild(element);

    getActiveBadgeTypesAdapter.emit(MOCK_BADGE_TYPES);

    return Promise.resolve().then(() => {
      const combobox = element.shadowRoot.querySelector("lightning-combobox");
      expect(combobox.options).toEqual([
        { label: "Team Player", value: "a02000000000001" }
      ]);
    });
  });

  it("disables the submit button until recipient, badge, and message are all set", () => {
    const element = createElement("c-kudos-wall", { is: KudosWall });
    document.body.appendChild(element);

    return Promise.resolve().then(() => {
      const button = element.shadowRoot.querySelector("lightning-button");
      expect(button.disabled).toBe(true);
    });
  });

  it("calls giveKudo with the selected recipient, badge type, and message on submit", async () => {
    giveKudo.mockResolvedValue({ Id: "a03000000000001" });

    const element = createElement("c-kudos-wall", { is: KudosWall });
    document.body.appendChild(element);

    getActiveBadgeTypesAdapter.emit(MOCK_BADGE_TYPES);
    await Promise.resolve();

    const recordPicker = element.shadowRoot.querySelector(
      "lightning-record-picker"
    );
    recordPicker.dispatchEvent(
      new CustomEvent("change", { detail: { recordId: "005000000000001" } })
    );

    const combobox = element.shadowRoot.querySelector("lightning-combobox");
    combobox.dispatchEvent(
      new CustomEvent("change", { detail: { value: "a02000000000001" } })
    );

    const textarea = element.shadowRoot.querySelector("lightning-textarea");
    textarea.dispatchEvent(
      new CustomEvent("change", { detail: { value: "Nice work!" } })
    );

    await Promise.resolve();

    const button = element.shadowRoot.querySelector("lightning-button");
    expect(button.disabled).toBe(false);

    button.click();

    await Promise.resolve();
    await Promise.resolve();

    expect(giveKudo).toHaveBeenCalledWith({
      recipientId: "005000000000001",
      badgeTypeId: "a02000000000001",
      message: "Nice work!"
    });
  });
});
