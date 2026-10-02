import { zodResolver } from '@hookform/resolvers/zod';
import { useState } from 'react';
import { useForm } from 'react-hook-form';
import { Link, useLocation, useNavigate } from 'react-router';
import { z } from 'zod';
import { Button } from '@/components/ui/button';
import { ErrorNotice } from '@/components/ui/feedback';
import { Field } from '@/components/ui/field';
import { Input } from '@/components/ui/input';
import { useAuth } from './use-auth';
import { AuthLayout } from './auth-layout';

const schema = z.object({
  email: z.email('Enter a valid email address'),
  password: z.string().min(1, 'Enter your password'),
});
type Values = z.infer<typeof schema>;

export function LoginPage() {
  const { login, state } = useAuth();
  const navigate = useNavigate();
  const location = useLocation();
  const [error, setError] = useState<unknown>(null);
  const { register, handleSubmit, formState } = useForm<Values>({ resolver: zodResolver(schema) });

  const from = (location.state as { from?: { pathname: string } } | null)?.from?.pathname ?? '/';

  const onSubmit = handleSubmit(async ({ email, password }) => {
    setError(null);
    try {
      await login(email, password);
      navigate(from, { replace: true });
    } catch (caught) {
      setError(caught);
    }
  });

  return (
    <AuthLayout
      title="Sign in"
      intro={
        state.status === 'anonymous' && state.expired
          ? 'Your session ended. Sign in again to continue.'
          : 'Open your organisation’s register.'
      }
      footer={
        <>
          New here?{' '}
          <Link to="/register" className="font-semibold text-ink underline-offset-2 hover:underline">
            Set up your school or company
          </Link>
        </>
      }
    >
      <form onSubmit={onSubmit} noValidate className="flex flex-col gap-4">
        {error !== null && <ErrorNotice error={error} />}
        <Field label="Email" error={formState.errors.email?.message}>
          <Input type="email" autoComplete="email" autoFocus {...register('email')} />
        </Field>
        <Field label="Password" error={formState.errors.password?.message}>
          <Input type="password" autoComplete="current-password" {...register('password')} />
        </Field>
        <Button type="submit" size="lg" loading={formState.isSubmitting} className="mt-2">
          Sign in
        </Button>
      </form>
    </AuthLayout>
  );
}
