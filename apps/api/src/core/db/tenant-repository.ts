import type { Model, QueryFilter, Types } from 'mongoose';

export type Id = string | Types.ObjectId;

/** Shape of a lean document as it comes back from MongoDB. */
export type Lean<T> = T & { _id: Types.ObjectId; createdAt: Date; updatedAt: Date };

/**
 * Base class for every repository that stores tenant-owned data.
 *
 * Every read and write goes through `scoped()`, which stamps `orgId` onto the filter.
 * Because `orgId` is the first parameter of every public method, the compiler makes it
 * impossible to query another organisation's data by forgetting a filter.
 */
export abstract class TenantRepository<TSchema extends { orgId: Types.ObjectId }> {
  protected constructor(protected readonly model: Model<TSchema>) {}

  protected scoped(orgId: Id, filter: QueryFilter<TSchema> = {}): QueryFilter<TSchema> {
    return { ...filter, orgId } as QueryFilter<TSchema>;
  }

  async findById(orgId: Id, id: Id): Promise<Lean<TSchema> | null> {
    return this.model
      .findOne(this.scoped(orgId, { _id: id } as QueryFilter<TSchema>))
      .lean<Lean<TSchema>>()
      .exec();
  }

  async exists(orgId: Id, filter: QueryFilter<TSchema> = {}): Promise<boolean> {
    return (await this.model.exists(this.scoped(orgId, filter))) !== null;
  }

  async count(orgId: Id, filter: QueryFilter<TSchema> = {}): Promise<number> {
    return this.model.countDocuments(this.scoped(orgId, filter)).exec();
  }

  async deleteById(orgId: Id, id: Id): Promise<boolean> {
    const result = await this.model.deleteOne(this.scoped(orgId, { _id: id } as QueryFilter<TSchema>)).exec();
    return result.deletedCount === 1;
  }
}

/** Converts a freshly created/saved Mongoose document into the same plain shape `.lean()` returns. */
export function toLean<T>(document: { toObject(): unknown }): Lean<T> {
  return document.toObject() as Lean<T>;
}
