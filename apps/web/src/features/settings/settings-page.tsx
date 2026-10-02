import { useSearchParams } from 'react-router';
import { PageHeader } from '@/components/layout/page-header';
import { Tabs } from '@/components/ui/tabs';
import { useCan } from '@/features/auth/use-auth';
import { DevicesSection, TeamSection } from './access-sections';
import { HolidaysSection, PeriodsSection } from './calendar-sections';
import { OrganizationSection, PolicySection } from './organization-sections';

const ALL_TABS = [
  { id: 'organization', label: 'Organisation', adminOnly: false },
  { id: 'rules', label: 'Attendance rules', adminOnly: false },
  { id: 'holidays', label: 'Holidays', adminOnly: false },
  { id: 'periods', label: 'Terms & periods', adminOnly: false },
  { id: 'devices', label: 'Check-in devices', adminOnly: true },
  { id: 'team', label: 'Team', adminOnly: true },
] as const;
type TabId = (typeof ALL_TABS)[number]['id'];

export function SettingsPage() {
  const isAdmin = useCan('ADMIN');
  const [params, setParams] = useSearchParams();
  const tabs = ALL_TABS.filter((tab) => isAdmin || !tab.adminOnly);
  const requested = params.get('tab');
  const active: TabId = tabs.find((tab) => tab.id === requested)?.id ?? 'organization';

  return (
    <>
      <PageHeader title="Settings">
        {isAdmin ? null : 'You can view these settings. Ask an admin to change them.'}
      </PageHeader>
      <Tabs
        label="Settings sections"
        tabs={tabs}
        value={active}
        onChange={(id) => setParams({ tab: id }, { replace: true })}
      />
      <div role="tabpanel" id={`panel-${active}`} aria-labelledby={`tab-${active}`} className="pt-6">
        {active === 'organization' && <OrganizationSection />}
        {active === 'rules' && <PolicySection />}
        {active === 'holidays' && <HolidaysSection />}
        {active === 'periods' && <PeriodsSection />}
        {active === 'devices' && <DevicesSection />}
        {active === 'team' && <TeamSection />}
      </div>
    </>
  );
}
