import { defineSchema, defineTable } from "convex/server";
import { v } from "convex/values";

export default defineSchema({
  timeEntries: defineTable({
    deviceEntryId: v.string(),
    slotStart: v.float64(),
    entryDescription: v.string(),
    submittedAt: v.float64(),
  }).index("by_deviceEntryId", ["deviceEntryId"]),
});
