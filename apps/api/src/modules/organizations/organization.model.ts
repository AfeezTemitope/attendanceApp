import { Schema, model } from 'mongoose';
import { POLICY_KINDS, type AttendancePolicyConfig } from '../attendance/policies/policy-config.js';

export const ORGANIZATION_TYPES = ['SCHOOL', 'COMPANY'] as const;
export type OrganizationType = (typeof ORGANIZATION_TYPES)[number];

export interface Organization {
  name: string;
  slug: string;
  type: OrganizationType;
  timezone: string;
  policy: AttendancePolicyConfig;
}

const policySchema = new Schema<AttendancePolicyConfig>(
  {
    kind: { type: String, enum: POLICY_KINDS, required: true },
    workDays: { type: [Number], required: true },
    opensAt: { type: String, required: true },
    lateAfter: { type: String, required: true },
    closesAt: { type: String },
    allowCheckOut: { type: Boolean, required: true },
  },
  { _id: false },
);

const organizationSchema = new Schema<Organization>(
  {
    name: { type: String, required: true, trim: true, maxlength: 120 },
    slug: { type: String, required: true, unique: true, lowercase: true, trim: true },
    type: { type: String, enum: ORGANIZATION_TYPES, required: true },
    timezone: { type: String, required: true, default: 'Africa/Lagos' },
    policy: { type: policySchema, required: true },
  },
  { timestamps: true },
);

export const OrganizationModel = model<Organization>('Organization', organizationSchema);
