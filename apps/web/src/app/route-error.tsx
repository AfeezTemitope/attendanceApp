import { isRouteErrorResponse, Link, useRouteError } from 'react-router';
import { APP_NAME } from './brand';

export function RouteError() {
  const error = useRouteError();
  const notFound = isRouteErrorResponse(error) && error.status === 404;
  return (
    <ErrorScreen
      title={notFound ? 'Page not found' : 'This page failed to load'}
      detail={
        notFound ? 'The link may be out of date.' : 'Reload the page. If it keeps happening, sign out and back in.'
      }
    />
  );
}

export function NotFound() {
  return <ErrorScreen title="Page not found" detail="The link may be out of date." />;
}

function ErrorScreen({ title, detail }: { title: string; detail: string }) {
  return (
    <main className="flex min-h-screen flex-col items-start justify-center gap-3 px-8 sm:px-16">
      <p className="font-display text-xl font-semibold text-ink">{APP_NAME}</p>
      <h1 className="text-4xl font-semibold">{title}</h1>
      <p className="text-muted">{detail}</p>
      <Link to="/" className="mt-2 font-semibold text-ink underline underline-offset-4">
        Go to today’s register
      </Link>
    </main>
  );
}
