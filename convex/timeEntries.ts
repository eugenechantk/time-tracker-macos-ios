import { query, mutation } from "./_generated/server";
import { v } from "convex/values";

export const list = query({
  args: {},
  handler: async (ctx) => {
    return await ctx.db.query("timeEntries").collect();
  },
});

export const upsert = mutation({
  args: {
    deviceEntryId: v.string(),
    slotStart: v.float64(),
    entryDescription: v.string(),
    submittedAt: v.float64(),
  },
  handler: async (ctx, args) => {
    const existing = await ctx.db
      .query("timeEntries")
      .withIndex("by_deviceEntryId", (q) =>
        q.eq("deviceEntryId", args.deviceEntryId)
      )
      .unique();

    if (existing) {
      await ctx.db.patch(existing._id, {
        entryDescription: args.entryDescription,
        submittedAt: args.submittedAt,
      });
      return existing._id;
    } else {
      return await ctx.db.insert("timeEntries", args);
    }
  },
});

export const remove = mutation({
  args: { deviceEntryId: v.string() },
  handler: async (ctx, args) => {
    const existing = await ctx.db
      .query("timeEntries")
      .withIndex("by_deviceEntryId", (q) =>
        q.eq("deviceEntryId", args.deviceEntryId)
      )
      .unique();

    if (existing) {
      await ctx.db.delete(existing._id);
    }
  },
});
