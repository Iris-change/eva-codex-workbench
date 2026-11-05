// Shared startup clock: mechanical announcements pause with the pilot confirmation.
export const SEQUENCE=Object.freeze({"duration":20,"lclStart":3,"lclEnd":6.4,"lclClearStart":6.8,"lclClearEnd":9.2,"syncStart":8.8,"syncFull":14.1,"hold":13.3,"transferStart":14.35,"transferEnd":15.45,"handoffStart":18.6,"handoffEnd":19.85,"fadeStart":19.85});
export function sceneTime(time){return time}
export function playbackTime(scene){return scene}
