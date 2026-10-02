import { zodResolver } from '@hookform/resolvers/zod';
import { useState } from 'react';
import { useForm, useWatch } from 'react-hook-form';
import { Link, useNavigate } from 'react-router';
import { z } from 'zod';
import { Button } from '@/components/ui/button';
import { ErrorNotice } from '@/components/ui/feedback';
import { Field } from '@/components/ui/field';
import { Input, Select } from '@/components/ui/input';
import { ApiError } from '@/lib/api-error';
import { cn } from '@/lib/cn';
import { timeZones } from '@/lib/time-zones';
import { useAuth } from './use-auth';
import { AuthLayout } from './auth-layout';

const schema = z.object({
  organizationName: z.string().trim().min(2, 'Enter at least 2 characters'),
  type: z.enum(['SCHOOL', 'COMPANY']),
  timezone: z.string().min(1),
  name: z.string().trim().min(2, 'Enter your full name'),
  email: z.email('Enter a valid email address'),
  password: z.string().min(8, 'Use at least 8 characters'),
});
type Values = z.infer<typeof schema>;

const FIELD_FROM_API: Record<string, keyof Values> = {
  'organization.name': 'organizationName',
  'organization.timezone': 'timezone',
  'user.name': 'name',
  'user.email': 'email',
  'user.password': 'password',
};

const TYPES = [
  { value: 'SCHOOL', title: 'School', detail: 'Check-in closes at a set time, e.g. 7:00–8:30.' },
  { value: 'COMPANY', title: 'Company', detail: 'Flexible arrival, late after a set time.' },
] as const;

export function RegisterPage() {
  const { register: signUp } = useAuth();
  const navigate = useNavigate();
  const [error, setError] = useState<unknown>(null);
  const {
    register,
    handleSubmit,
    formState,
    setError: setFieldError,
    control,
  } = useForm<Values>({
    resolver: zodResolver(schema),
    defaultValues: { type: 'SCHOOL', timezone: 'Africa/Lagos' },
  });
  const type = useWatch({ control, name: 'type' });

  const onSubmit = handleSubmit(async (values) => {
    setError(null);
    try {
      await signUp({
        organization: { name: values.organizationName, type: values.type, timezone: values.timezone },
        user: { name: values.name, email: values.email, password: values.password },
      });
      navigate('/', { replace: true });
    } catch (caught) {
      if (caught instanceof ApiError && caught.code === 'VALIDATION_ERROR') {
        for (const [path, message] of Object.entries(caught.fieldErrors)) {
          const field = FIELD_FROM_API[path];
          if (field) setFieldError(field, { message });
        }
      } else {
        setError(caught);
      }
    }
  });

  return (
    <AuthLayout
      title="Set up your register"
      intro="Create your organisation. You can add people and devices next."
      footer={
        <>
          Already set up?{' '}
          <Link to="/login" className="font-semibold text-ink underline-offset-2 hover:underline">
            Sign in
          </Link>
        </>
      }
    >
      <form onSubmit={onSubmit} noValidate className="flex flex-col gap-4">
        {error !== null && <ErrorNotice error={error} />}
        <Field label="School or company name" error={formState.errors.organizationName?.message}>
          <Input autoFocus autoComplete="organization" {...register('organizationName')} />
        </Field>

        <fieldset className="flex flex-col gap-2">
          <legend className="mb-1.5 text-sm font-medium">This is a</legend>
          <div className="grid grid-cols-2 gap-2">
            {TYPES.map((option) => (
              <label
                key={option.value}
                className={cn(
                  'cursor-pointer rounded-lg border px-3 py-2.5 transition-colors has-[:focus-visible]:outline-2 has-[:focus-visible]:outline-ink',
                  type === option.value ? 'border-ink bg-ink-wash' : 'border-rule hover:border-ink-soft/60',
                )}
              >
                <input type="radio" value={option.value} className="sr-only" {...register('type')} />
                <span className="block font-semibold text-ink">{option.title}</span>
                <span className="block text-xs text-muted">{option.detail}</span>
              </label>
            ))}
          </div>
        </fieldset>

        <Field label="Timezone" error={formState.errors.timezone?.message}>
          <Select {...register('timezone')}>
            {timeZones().map((zone) => (
              <option key={zone} value={zone}>
                {zone.replaceAll('_', ' ')}
              </option>
            ))}
          </Select>
        </Field>

        <div className="my-1 border-t border-rule" />

        <Field label="Your full name" error={formState.errors.name?.message}>
          <Input autoComplete="name" {...register('name')} />
        </Field>
        <Field label="Email" error={formState.errors.email?.message}>
          <Input type="email" autoComplete="email" {...register('email')} />
        </Field>
        <Field label="Password" hint="At least 8 characters." error={formState.errors.password?.message}>
          <Input type="password" autoComplete="new-password" {...register('password')} />
        </Field>
        <Button type="submit" size="lg" loading={formState.isSubmitting} className="mt-2">
          Create organisation
        </Button>
      </form>
    </AuthLayout>
  );
}
