#!/bin/bash

# =============================================================================
# DRTP CRM - ONE-CLICK DEPLOY
# =============================================================================

set -e

PROJECT_NAME="drtp-crm"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

TOTAL_STEPS=12
CURRENT_STEP=0

progress() {
    CURRENT_STEP=$((CURRENT_STEP + 1))
    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}  Step $CURRENT_STEP of $TOTAL_STEPS: $1${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

success() { echo -e "${GREEN}✅ $1${NC}"; }
warning() { echo -e "${YELLOW}⚠️  $1${NC}"; }
error() { echo -e "${RED}❌ $1${NC}"; exit 1; }

# =============================================================================
# STEP 1: Check Prerequisites
# =============================================================================
progress "Checking Prerequisites"

if ! command -v node &> /dev/null; then
    error "Node.js is not installed. Please install Node.js 18+ from https://nodejs.org"
fi

NODE_VERSION=$(node -v | cut -d'v' -f2 | cut -d'.' -f1)
if [ "$NODE_VERSION" -lt 18 ]; then
    error "Node.js version 18+ required. Current: $(node -v)"
fi
success "Node.js $(node -v) installed"

if ! command -v git &> /dev/null; then
    error "Git is not installed"
fi
success "Git installed"

# =============================================================================
# STEP 2: Create Project Structure
# =============================================================================
progress "Creating Project Structure: $PROJECT_NAME"

mkdir -p $PROJECT_NAME
cd $PROJECT_NAME

mkdir -p apps/api/src/{config,integrations,middleware,routes,lib}
mkdir -p apps/web/app/\(dashboard\)/{contacts,deals,tasks,reports,admin/costs,settings}
mkdir -p apps/web/components/{contacts,deals,tasks,layout,setup,dashboard,ui,forms}
mkdir -p apps/web/lib
mkdir -p apps/web/hooks
mkdir -p apps/web/types
mkdir -p apps/web/public
mkdir -p packages/database/prisma
mkdir -p packages/shared
mkdir -p scripts

success "Project directories created for $PROJECT_NAME"

# =============================================================================
# STEP 3: Create Root Configuration Files
# =============================================================================
progress "Creating Configuration Files"

cat > package.json << EOF
{
  "name": "$PROJECT_NAME",
  "version": "1.0.0",
  "private": true,
  "description": "Dr Take Profit CRM - Free Tier Deployment",
  "scripts": {
    "build": "turbo run build",
    "dev": "turbo run dev",
    "start": "cd apps/api && npm start",
    "db:generate": "cd packages/database && prisma generate",
    "db:migrate": "cd packages/database && prisma migrate dev",
    "db:deploy": "cd packages/database && prisma migrate deploy",
    "db:studio": "cd packages/database && prisma studio",
    "db:seed": "cd packages/database && tsx prisma/seed.ts",
    "lint": "turbo run lint",
    "clean": "turbo run clean && rm -rf node_modules"
  },
  "devDependencies": {
    "turbo": "^1.11.0",
    "typescript": "^5.3.0",
    "tsx": "^4.7.0"
  },
  "workspaces": [
    "apps/*",
    "packages/*"
  ],
  "engines": {
    "node": ">=18.0.0"
  }
}
EOF

cat > turbo.json << 'EOF'
{
  "$schema": "https://turbo.build/schema.json",
  "globalDependencies": ["**/.env.*local"],
  "pipeline": {
    "build": {
      "dependsOn": ["^build"],
      "outputs": [".next/**", "!.next/cache/**", "dist/**"]
    },
    "dev": {
      "cache": false,
      "persistent": true
    },
    "lint": {
      "outputs": []
    },
    "clean": {
      "cache": false
    }
  }
}
EOF

cat > docker-compose.yml << 'EOF'
version: '3.8'

services:
  postgres:
    image: postgres:15-alpine
    container_name: drtp-postgres
    environment:
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: postgres
      POSTGRES_DB: drtp_crm
    ports:
      - "5432:5432"
    volumes:
      - postgres_data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U postgres"]
      interval: 5s
      timeout: 5s
      retries: 5

  redis:
    image: redis:7-alpine
    container_name: drtp-redis
    ports:
      - "6379:6379"
    volumes:
      - redis_data:/data
    command: redis-server --appendonly yes
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 5s
      timeout: 3s
      retries: 5

volumes:
  postgres_data:
  redis_data:
EOF

cat > .gitignore << 'EOF'
# Dependencies
node_modules/
.pnp
.pnp.js

# Testing
coverage/

# Next.js
.next/
out/

# Production
build/
dist/

# Misc
.DS_Store
*.pem
.env
.env.local
.env.development.local
.env.test.local
.env.production.local

# Debug
npm-debug.log*
yarn-debug.log*
yarn-error.log*

# Turbo
.turbo/

# IDE
.idea/
.vscode/
*.swp
*.swo

# Logs
logs/
*.log

# Database
*.db
*.sqlite
EOF

success "Root configuration files created"

# =============================================================================
# STEP 4: Create Database Package
# =============================================================================
progress "Creating Database Package"

cat > packages/database/package.json << 'EOF'
{
  "name": "@packages/database",
  "version": "1.0.0",
  "main": "./dist/index.js",
  "types": "./dist/index.d.ts",
  "scripts": {
    "build": "tsc",
    "generate": "prisma generate",
    "migrate": "prisma migrate dev",
    "deploy": "prisma migrate deploy",
    "studio": "prisma studio",
    "seed": "tsx prisma/seed.ts"
  },
  "dependencies": {
    "@prisma/client": "^5.7.0"
  },
  "devDependencies": {
    "@types/node": "^20.10.0",
    "prisma": "^5.7.0",
    "tsx": "^4.7.0",
    "typescript": "^5.3.0"
  }
}
EOF

cat > packages/database/prisma/schema.prisma << 'EOF'
generator client {
  provider = "prisma-client-js"
}

datasource db {
  provider = "postgresql"
  url      = env("DATABASE_URL")
}

model User {
  id            String    @id @default(uuid())
  email         String    @unique
  passwordHash  String    @map("password_hash")
  fullName      String    @map("full_name")
  role          UserRole  @default(CALLER)
  avatarUrl     String?   @map("avatar_url")
  isActive      Boolean   @default(true) @map("is_active")
  timezone      String    @default("Europe/London")
  
  assignedContactsCaller  Contact[] @relation("AssignedCaller")
  assignedContactsCloser  Contact[] @relation("AssignedCloser")
  ownedDeals              Deal[]
  tasksAssigned           Task[]    @relation("TaskAssignee")
  tasksCreated            Task[]    @relation("TaskCreator")
  activities              Activity[]
  emailLogs               EmailLog[]
  
  createdAt DateTime @default(now()) @map("created_at")
  updatedAt DateTime @updatedAt @map("updated_at")

  @@map("users")
}

enum UserRole {
  ADMIN
  CALLER
  CLOSER
  TRADER
  VIEWER
}

model LeadSource {
  id          String   @id @default(uuid())
  name        String
  type        SourceType
  isActive    Boolean  @default(true) @map("is_active")
  config      Json?
  
  contacts    Contact[]
  
  createdAt   DateTime @default(now()) @map("created_at")
  @@map("lead_sources")
}

enum SourceType {
  META_ADS
  GOOGLE_ADS
  TIKTOK_ADS
  LINKEDIN_ADS
  ORGANIC
  REFERRAL
  API
  MANUAL
  OTHER
}

model Contact {
  id                  String      @id @default(uuid())
  
  sourceId            String      @map("source_id")
  sourceType          SourceType  @map("source_type")
  
  fullName            String      @map("full_name")
  email               String      @unique
  phone               String?
  age                 Int?
  country             String?
  city                String?
  timezone            String?
  
  status              ContactStatus @default(NEW)
  previousStatus      String?     @map("previous_status")
  statusChangedAt     DateTime?   @map("status_changed_at")
  
  assignedCallerId    String?     @map("assigned_caller_id")
  assignedCloserId    String?     @map("assigned_closer_id")
  
  riskProfile         RiskProfile? @map("risk_profile")
  riskScore           Int?         @map("risk_score")
  
  leadScore           Int          @default(0) @map("lead_score")
  leadTemperature     Temperature  @default(COLD)
  lastActivityAt      DateTime?    @map("last_activity_at")
  nextFollowUpAt      DateTime?    @map("next_follow_up_at")
  
  webinarRegisteredAt DateTime?    @map("webinar_registered_at")
  webinarAttendedAt   DateTime?    @map("webinar_attended_at")
  webinarId           String?      @map("webinar_id")
  
  gdprConsent         Boolean      @default(false) @map("gdpr_consent")
  consentDate         DateTime?    @map("consent_date")
  marketingConsent    Boolean      @default(false) @map("marketing_consent")
  
  customFields        Json         @default("{}") @map("custom_fields")
  
  source              LeadSource   @relation(fields: [sourceId], references: [id])
  assignedCaller      User?        @relation("AssignedCaller", fields: [assignedCallerId], references: [id])
  assignedCloser      User?        @relation("AssignedCloser", fields: [assignedCloserId], references: [id])
  
  interactions        Interaction[]
  deals               Deal[]
  tasks               Task[]
  activities          Activity[]
  riskAssessments     RiskAssessment[]
  
  createdAt           DateTime     @default(now()) @map("created_at")
  updatedAt           DateTime     @updatedAt @map("updated_at")

  @@index([status])
  @@index([assignedCallerId])
  @@index([assignedCloserId])
  @@index([sourceId])
  @@index([createdAt])
  @@map("contacts")
}

enum ContactStatus {
  NEW
  CONTACTED
  WEBINAR_REGISTERED
  WEBINAR_ATTENDED
  RISK_FORM_SENT
  RISK_FORM_COMPLETED
  CALL_BOOKED
  OFFER_PRESENTED
  CLOSED_WON
  CLOSED_LOST
  NURTURE
}

enum RiskProfile {
  CONSERVATIVE
  MODERATE
  AGGRESSIVE
}

enum Temperature {
  COLD
  WARM
  HOT
}

model RiskAssessment {
  id              String   @id @default(uuid())
  contactId       String   @map("contact_id")
  
  experienceLevel String?  @map("experience_level")
  monthlyIncome   String?  @map("monthly_income")
  capitalAvailable Decimal? @map("capital_available") @db.Decimal(12, 2)
  riskTolerance   String?  @map("risk_tolerance")
  timeAvailable   Int?     @map("time_available")
  tradingGoals    String?  @map("trading_goals")
  biggestStruggle String?  @map("biggest_struggle")
  
  profileSummary  String?  @map("profile_summary")
  recommendedStrategy String? @map("recommended_strategy")
  riskScore       Int?     @map("risk_score")
  
  status          FormStatus @default(PENDING)
  sentAt          DateTime?  @map("sent_at")
  completedAt     DateTime?  @map("completed_at")
  reminderCount   Int        @default(0) @map("reminder_count")
  
  contact         Contact    @relation(fields: [contactId], references: [id], onDelete: Cascade)
  
  createdAt       DateTime   @default(now()) @map("created_at")
  @@map("risk_assessments")
}

enum FormStatus {
  PENDING
  COMPLETED
  EXPIRED
}

model Deal {
  id              String     @id @default(uuid())
  contactId       String     @map("contact_id")
  title           String
  
  stage           DealStage
  previousStage   String?    @map("previous_stage")
  stageEnteredAt  DateTime   @default(now()) @map("stage_entered_at")
  
  ownerId         String     @map("owner_id")
  
  value           Decimal    @db.Decimal(12, 2)
  currency        String     @default("EUR")
  offerType       OfferType  @map("offer_type")
  
  probability     Int        @default(20)
  expectedCloseDate DateTime? @map("expected_close_date")
  actualCloseDate DateTime?  @map("actual_close_date")
  
  lossReason      String?    @map("loss_reason")
  lossNotes       String?    @map("loss_notes")
  
  contact         Contact    @relation(fields: [contactId], references: [id], onDelete: Cascade)
  owner           User       @relation(fields: [ownerId], references: [id])
  
  createdAt       DateTime   @default(now()) @map("created_at")
  updatedAt       DateTime   @updatedAt @map("updated_at")

  @@index([stage])
  @@index([ownerId])
  @@map("deals")
}

enum DealStage {
  NEW_LEAD
  CONTACTED
  WEBINAR_REGISTERED
  WEBINAR_ATTENDED
  RISK_ASSESSMENT_COMPLETED
  STRATEGY_CALL_BOOKED
  OFFER_PRESENTED
  NEGOTIATION
  CLOSED_WON
  CLOSED_LOST
}

enum OfferType {
  LIVE_SESSION
  GROUP_MENTORSHIP
  VIP_MENTORSHIP
  CUSTOM
}

model Interaction {
  id          String   @id @default(uuid())
  contactId   String   @map("contact_id")
  userId      String   @map("user_id")
  
  type        InteractionType
  channel     String   @default("phone")
  direction   Direction @default(OUTBOUND)
  
  notes       String?
  outcome     String?
  durationMin Int?     @map("duration_min")
  
  scheduledAt DateTime? @map("scheduled_at")
  completedAt DateTime? @map("completed_at")
  
  metadata    Json?
  
  contact     Contact  @relation(fields: [contactId], references: [id], onDelete: Cascade)
  user        User     @relation(fields: [userId], references: [id])
  
  createdAt   DateTime @default(now()) @map("created_at")
  @@map("interactions")
}

enum InteractionType {
  CALL
  EMAIL
  MEETING
  NOTE
  WHATSAPP
  SMS
}

enum Direction {
  INBOUND
  OUTBOUND
}

model Task {
  id          String     @id @default(uuid())
  contactId   String?    @map("contact_id")
  
  assignedTo  String     @map("assigned_to")
  createdBy   String     @map("created_by")
  
  title       String
  description String?
  type        TaskType
  priority    Priority   @default(MEDIUM)
  
  dueDate     DateTime   @map("due_date")
  status      TaskStatus @default(PENDING)
  
  completedAt DateTime?  @map("completed_at")
  completedBy String?    @map("completed_by")
  
  contact     Contact?   @relation(fields: [contactId], references: [id], onDelete: SetNull)
  assignee    User       @relation("TaskAssignee", fields: [assignedTo], references: [id])
  creator     User       @relation("TaskCreator", fields: [createdBy], references: [id])
  
  createdAt   DateTime   @default(now()) @map("created_at")
  updatedAt   DateTime   @updatedAt @map("updated_at")

  @@index([assignedTo, status])
  @@index([dueDate])
  @@map("tasks")
}

enum TaskType {
  CALL
  EMAIL
  FOLLOW_UP
  MEETING
  ADMIN
  WEBINAR_REMINDER
}

enum Priority {
  LOW
  MEDIUM
  HIGH
  URGENT
}

enum TaskStatus {
  PENDING
  IN_PROGRESS
  COMPLETED
  CANCELLED
}

model Activity {
  id          String   @id @default(uuid())
  contactId   String   @map("contact_id")
  userId      String?  @map("user_id")
  dealId      String?  @map("deal_id")
  
  type        ActivityType
  description String
  metadata    Json?
  
  contact     Contact  @relation(fields: [contactId], references: [id], onDelete: Cascade)
  
  createdAt   DateTime @default(now()) @map("created_at")
  @@index([contactId, createdAt])
  @@map("activities")
}

enum ActivityType {
  STATUS_CHANGE
  STAGE_CHANGE
  EMAIL_SENT
  EMAIL_OPENED
  EMAIL_CLICKED
  CALL_MADE
  NOTE_ADDED
  TASK_COMPLETED
  DEAL_CREATED
  DEAL_WON
  DEAL_LOST
  TAG_ADDED
  ASSIGNED
}

model EmailTemplate {
  id          String   @id @default(uuid())
  name        String
  category    TemplateCategory
  subject     String
  bodyHtml    String   @map("body_html")
  bodyText    String?  @map("body_text")
  variables   Json     @default("[]")
  
  fromName    String?  @map("from_name")
  fromEmail   String?  @map("from_email")
  
  isActive    Boolean  @default(true) @map("is_active")
  
  emailLogs   EmailLog[]
  
  createdAt   DateTime @default(now()) @map("created_at")
  updatedAt   DateTime @updatedAt @map("updated_at")
  @@map("email_templates")
}

enum TemplateCategory {
  WELCOME
  WEBINAR_INVITE
  WEBINAR_FOLLOWUP
  RISK_FORM
  RISK_REMINDER
  CALL_BOOKING
  CALL_CONFIRMATION
  OFFER
  NURTURE
  ADMIN
}

model EmailLog {
  id          String   @id @default(uuid())
  contactId   String   @map("contact_id")
  templateId  String?  @map("template_id")
  userId      String?  @map("user_id")
  
  subject     String
  bodyHtml    String   @map("body_html")
  toEmail     String   @map("to_email")
  fromEmail   String   @map("from_email")
  
  status      EmailStatus @default(QUEUED)
  providerId  String?  @map("provider_id")
  
  openedAt    DateTime? @map("opened_at")
  openCount   Int       @default(0) @map("open_count")
  clickedAt   DateTime? @map("clicked_at")
  clickCount  Int       @default(0) @map("click_count")
  
  sentAt      DateTime? @map("sent_at")
  deliveredAt DateTime? @map("delivered_at")
  
  contact     Contact  @relation(fields: [contactId], references: [id], onDelete: Cascade)
  
  createdAt   DateTime @default(now()) @map("created_at")
  @@index([contactId])
  @@index([status])
  @@map("email_logs")
}

enum EmailStatus {
  QUEUED
  SENT
  DELIVERED
  OPENED
  CLICKED
  BOUNCED
  FAILED
}

model WebhookLog {
  id          String   @id @default(uuid())
  source      String
  eventType   String   @map("event_type")
  payload     Json
  headers     Json?
  processed   Boolean  @default(false)
  error       String?
  contactId   String?  @map("contact_id")
  
  createdAt   DateTime @default(now()) @map("created_at")
  @@index([source, createdAt])
  @@map("webhook_logs")
}
EOF

cat > packages/database/prisma/seed.ts << 'EOF'
import { PrismaClient, UserRole, SourceType } from '@prisma/client';
import bcrypt from 'bcryptjs';

const prisma = new PrismaClient();

async function main() {
  console.log('🌱 Seeding database...');

  const adminPassword = await bcrypt.hash('admin123', 10);
  const admin = await prisma.user.upsert({
    where: { email: 'admin@dr-take-profit.com' },
    update: {},
    create: {
      email: 'admin@dr-take-profit.com',
      passwordHash: adminPassword,
      fullName: 'Admin User',
      role: UserRole.ADMIN,
      isActive: true,
    },
  });
  console.log('✅ Created admin user:', admin.email);

  const callerPassword = await bcrypt.hash('caller123', 10);
  const caller = await prisma.user.upsert({
    where: { email: 'caller@dr-take-profit.com' },
    update: {},
    create: {
      email: 'caller@dr-take-profit.com',
      passwordHash: callerPassword,
      fullName: 'Sales Caller',
      role: UserRole.CALLER,
      isActive: true,
    },
  });
  console.log('✅ Created caller user:', caller.email);

  const metaSource = await prisma.leadSource.upsert({
    where: { id: '00000000-0000-0000-0000-000000000001' },
    update: {},
    create: {
      id: '00000000-0000-0000-0000-000000000001',
      name: 'Meta Ads',
      type: SourceType.META_ADS,
      isActive: true,
    },
  });
  console.log('✅ Created lead source:', metaSource.name);

  const templates = [
    {
      name: 'Welcome Email',
      category: 'WELCOME',
      subject: 'Welcome to Dr. Take Profit!',
      bodyHtml: '<h1>Welcome {{firstName}}!</h1><p>Thank you for joining us.</p>',
    },
    {
      name: 'Webinar Follow-up',
      category: 'WEBINAR_FOLLOWUP',
      subject: 'Thanks for attending our webinar',
      bodyHtml: '<h1>Hi {{firstName}},</h1><p>Thanks for attending. Here is your risk assessment: {{riskFormLink}}</p>',
    },
    {
      name: 'Risk Form Reminder',
      category: 'RISK_REMINDER',
      subject: 'Complete your risk assessment',
      bodyHtml: '<h1>Hi {{firstName}},</h1><p>Please complete your risk assessment: {{riskFormLink}}</p>',
    },
  ];

  for (const template of templates) {
    await prisma.emailTemplate.upsert({
      where: { name: template.name },
      update: {},
      create: template,
    });
  }
  console.log('✅ Created email templates');

  console.log('✅ Seeding complete!');
}

main()
  .catch((e) => {
    console.error('❌ Seed error:', e);
    process.exit(1);
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
EOF

success "Database package created"

# =============================================================================
# STEP 5: Create Backend API
# =============================================================================
progress "Creating Backend API"

cat > apps/api/package.json << 'EOF'
{
  "name": "@apps/api",
  "version": "1.0.0",
  "scripts": {
    "dev": "tsx watch src/index.ts",
    "build": "tsc",
    "start": "node dist/index.js",
    "worker": "node dist/workers/index.js"
  },
  "dependencies": {
    "@packages/database": "*",
    "bcryptjs": "^2.4.3",
    "compression": "^1.7.4",
    "cors": "^2.8.5",
    "dotenv": "^16.3.1",
    "express": "^4.18.2",
    "helmet": "^7.1.0",
    "ioredis": "^5.3.2",
    "jsonwebtoken": "^9.0.2",
    "bullmq": "^5.1.0",
    "zod": "^3.22.4"
  },
  "devDependencies": {
    "@types/bcryptjs": "^2.4.6",
    "@types/compression": "^1.7.5",
    "@types/cors": "^2.8.17",
    "@types/express": "^4.17.21",
    "@types/jsonwebtoken": "^9.0.5",
    "@types/node": "^20.10.0",
    "tsx": "^4.7.0",
    "typescript": "^5.3.0"
  }
}
EOF

cat > apps/api/tsconfig.json << 'EOF'
{
  "compilerOptions": {
    "target": "ES2020",
    "module": "commonjs",
    "lib": ["ES2020"],
    "outDir": "./dist",
    "rootDir": "./src",
    "strict": true,
    "esModuleInterop": true,
    "skipLibCheck": true,
    "forceConsistentCasingInFileNames": true,
    "resolveJsonModule": true,
    "declaration": true,
    "declarationMap": true,
    "sourceMap": true,
    "baseUrl": ".",
    "paths": {
      "@packages/database": ["../../packages/database"],
      "@packages/database/*": ["../../packages/database/*"]
    }
  },
  "include": ["src/**/*"],
  "exclude": ["node_modules", "dist"]
}
EOF

cat > apps/api/src/index.ts << 'EOF'
import express from 'express';
import cors from 'cors';
import helmet from 'helmet';
import compression from 'compression';
import dotenv from 'dotenv';
import path from 'path';

dotenv.config({ path: path.join(__dirname, '../../../.env') });

import { PrismaClient } from '@packages/database';
import { Queue } from 'bullmq';
import IORedis from 'ioredis';

import webhookRoutes from './routes/webhooks';
import contactRoutes from './routes/contacts';
import dealRoutes from './routes/deals';
import taskRoutes from './routes/tasks';
import authRoutes from './routes/auth';
import reportRoutes from './routes/reports';
import adminRoutes from './routes/admin';

const app = express();

export const prisma = new PrismaClient();
export const redis = new IORedis(process.env.REDIS_URL || 'redis://localhost:6379');

export const emailQueue = new Queue('emails', { connection: redis });
export const automationQueue = new Queue('automations', { connection: redis });

app.use(helmet());
app.use(cors({
  origin: process.env.FRONTEND_URL || 'http://localhost:3000',
  credentials: true
}));
app.use(compression());
app.use(express.json());
app.use(express.urlencoded({ extended: true }));

if (process.env.NODE_ENV !== 'production') {
  app.use((req, res, next) => {
    console.log(`${req.method} ${req.path}`);
    next();
  });
}

app.get('/health', (req, res) => {
  res.json({ 
    status: 'ok', 
    timestamp: new Date().toISOString(),
    version: '1.0.0',
    environment: process.env.NODE_ENV || 'development'
  });
});

app.use('/webhooks', webhookRoutes);
app.use('/api/auth', authRoutes);
app.use('/api/contacts', contactRoutes);
app.use('/api/deals', dealRoutes);
app.use('/api/tasks', taskRoutes);
app.use('/api/reports', reportRoutes);
app.use('/api/admin', adminRoutes);

app.use((err: any, req: express.Request, res: express.Response, next: express.NextFunction) => {
  console.error('Error:', err);
  res.status(err.status || 500).json({
    error: err.message || 'Internal server error',
    code: err.code,
    ...(process.env.NODE_ENV !== 'production' && { stack: err.stack })
  });
});

const PORT = process.env.PORT || 3001;

app.listen(PORT, () => {
  console.log(`🚀 DRTP CRM API running on port ${PORT}`);
  console.log(`📊 Health check: http://localhost:${PORT}/health`);
});

process.on('SIGTERM', async () => {
  console.log('SIGTERM received, shutting down gracefully');
  await prisma.$disconnect();
  await redis.quit();
  process.exit(0);
});
EOF

# Create routes directory and files
mkdir -p apps/api/src/routes

cat > apps/api/src/routes/webhooks.ts << 'EOF'
import { Router } from 'express';
import crypto from 'crypto';
import { prisma } from '../index';

const router = Router();

router.get('/meta', (req, res) => {
  const mode = req.query['hub.mode'];
  const token = req.query['hub.verify_token'];
  const challenge = req.query['hub.challenge'];

  if (mode === 'subscribe' && token === process.env.META_WEBHOOK_VERIFY_TOKEN) {
    console.log('✅ Meta webhook verified');
    res.status(200).send(challenge);
  } else {
    res.sendStatus(403);
  }
});

router.post('/meta', async (req, res) => {
  try {
    const signature = req.headers['x-hub-signature-256'] as string;
    const secret = process.env.META_WEBHOOK_SECRET;
    
    if (secret && signature) {
      const expected = crypto
        .createHmac('sha256', secret)
        .update(JSON.stringify(req.body))
        .digest('hex');
      
      if (signature.replace('sha256=', '') !== expected) {
        return res.status(401).json({ error: 'Invalid signature' });
      }
    }

    for (const entry of req.body.entry || []) {
      for (const change of entry.changes || []) {
        if (change.value?.leadgen_id) {
          await processMetaLead(change.value);
        }
      }
    }

    res.status(200).json({ received: true });
  } catch (error) {
    console.error('Webhook error:', error);
    await prisma.webhookLog.create({
      data: {
        source: 'meta',
        eventType: 'leadgen',
        payload: req.body,
        processed: false,
        error: error instanceof Error ? error.message : 'Unknown error'
      }
    });
    res.status(500).json({ error: 'Processing failed' });
  }
});

async function processMetaLead(leadData: any) {
  const fields: Record<string, string> = {};
  for (const field of leadData.field_data || []) {
    fields[field.name.toLowerCase().replace(/ /g, '_')] = field.values?.[0];
  }

  const email = fields.email?.toLowerCase();
  const phone = fields.phone_number?.replace(/\D/g, '');

  const existing = await prisma.contact.findFirst({
    where: {
      OR: [
        { email: email || '' },
        { phone: phone || '' }
      ]
    }
  });

  if (existing) {
    await prisma.contact.update({
      where: { id: existing.id },
      data: { lastActivityAt: new Date() }
    });
    await logActivity(existing.id, 'Lead updated from Meta', { metaLeadId: leadData.leadgen_id });
    return;
  }

  let source = await prisma.leadSource.findFirst({
    where: { type: 'META_ADS' }
  });

  if (!source) {
    source = await prisma.leadSource.create({
      data: {
        name: 'Meta Ads',
        type: 'META_ADS',
        isActive: true
      }
    });
  }

  const callers = await prisma.user.findMany({
    where: { role: 'CALLER', isActive: true },
    include: { _count: { select: { assignedContactsCaller: true } } }
  });

  const assignedCaller = callers.sort((a, b) => 
    a._count.assignedContactsCaller - b._count.assignedContactsCaller
  )[0];

  const contact = await prisma.contact.create({
    data: {
      sourceId: source.id,
      sourceType: 'META_ADS',
      fullName: fields.full_name || `${fields.first_name || ''} ${fields.last_name || ''}`.trim() || 'Unknown',
      email: email || '',
      phone: phone || fields.phone_number,
      age: fields.age ? parseInt(fields.age) : null,
      country: fields.country,
      city: fields.city,
      status: 'NEW',
      assignedCallerId: assignedCaller?.id,
      gdprConsent: true,
      consentDate: new Date(),
      lastActivityAt: new Date()
    }
  });

  await logActivity(contact.id, 'Lead created from Meta Ads', {
    campaignId: leadData.campaign_id,
    adId: leadData.ad_id
  });

  console.log(`✅ Created contact: ${contact.fullName} (${contact.email})`);
}

async function logActivity(contactId: string, description: string, metadata?: any) {
  await prisma.activity.create({
    data: {
      contactId,
      type: 'NOTE_ADDED',
      description,
      metadata
    }
  });
}

export default router;
EOF

cat > apps/api/src/routes/auth.ts << 'EOF'
import { Router } from 'express';
import bcrypt from 'bcryptjs';
import jwt from 'jsonwebtoken';
import { z } from 'zod';
import { prisma } from '../index';

const router = Router();

router.post('/login', async (req, res) => {
  try {
    const schema = z.object({
      email: z.string().email(),
      password: z.string().min(6)
    });

    const { email, password } = schema.parse(req.body);

    const user = await prisma.user.findUnique({
      where: { email: email.toLowerCase() }
    });

    if (!user || !user.isActive) {
      return res.status(401).json({ error: 'Invalid credentials' });
    }

    const isValid = await bcrypt.compare(password, user.passwordHash);
    if (!isValid) {
      return res.status(401).json({ error: 'Invalid credentials' });
    }

    const token = jwt.sign(
      { userId: user.id, email: user.email, role: user.role },
      process.env.JWT_SECRET!,
      { expiresIn: '7d' }
    );

    res.json({
      token,
      user: {
        id: user.id,
        email: user.email,
        fullName: user.fullName,
        role: user.role
      }
    });
  } catch (error) {
    res.status(400).json({ error: 'Invalid request' });
  }
});

router.post('/setup', async (req, res) => {
  try {
    const { email, password } = req.body;
    
    const existing = await prisma.user.findUnique({ where: { email } });
    if (!existing) {
      return res.status(404).json({ error: 'User not found. Create user in database first.' });
    }

    const hashedPassword = await bcrypt.hash(password, 10);
    await prisma.user.update({
      where: { email },
      data: { passwordHash: hashedPassword }
    });

    res.json({ message: 'Password set successfully' });
  } catch (error) {
    res.status(500).json({ error: 'Setup failed' });
  }
});

export default router;
EOF

cat > apps/api/src/routes/contacts.ts << 'EOF'
import { Router } from 'express';
import { z } from 'zod';
import { prisma } from '../index';

const router = Router();

router.get('/', async (req, res) => {
  try {
    const { status, search, page = '1', limit = '50' } = req.query;
    
    const where: any = {};
    if (status) where.status = status;
    if (search) {
      where.OR = [
        { fullName: { contains: search as string, mode: 'insensitive' } },
        { email: { contains: search as string, mode: 'insensitive' } }
      ];
    }

    const skip = (parseInt(page as string) - 1) * parseInt(limit as string);
    
    const [contacts, total] = await Promise.all([
      prisma.contact.findMany({
        where,
        include: {
          assignedCaller: { select: { id: true, fullName: true, avatarUrl: true } },
          assignedCloser: { select: { id: true, fullName: true, avatarUrl: true } },
          _count: { select: { tasks: true, activities: true } }
        },
        orderBy: { createdAt: 'desc' },
        skip,
        take: parseInt(limit as string)
      }),
      prisma.contact.count({ where })
    ]);

    res.json({
      data: contacts,
      pagination: {
        page: parseInt(page as string),
        limit: parseInt(limit as string),
        total,
        pages: Math.ceil(total / parseInt(limit as string))
      }
    });
  } catch (error) {
    res.status(500).json({ error: 'Failed to fetch contacts' });
  }
});

router.get('/:id', async (req, res) => {
  try {
    const contact = await prisma.contact.findUnique({
      where: { id: req.params.id },
      include: {
        assignedCaller: true,
        assignedCloser: true,
        deals: true,
        tasks: {
          orderBy: { dueDate: 'asc' },
          include: { assignee: { select: { fullName: true } } }
        },
        activities: { orderBy: { createdAt: 'desc' }, take: 50 },
        riskAssessments: { orderBy: { createdAt: 'desc' } }
      }
    });

    if (!contact) return res.status(404).json({ error: 'Contact not found' });
    res.json(contact);
  } catch (error) {
    res.status(500).json({ error: 'Failed to fetch contact' });
  }
});

router.patch('/:id/status', async (req, res) => {
  try {
    const schema = z.object({
      status: z.enum([
        'NEW', 'CONTACTED', 'WEBINAR_REGISTERED', 'WEBINAR_ATTENDED',
        'RISK_FORM_SENT', 'RISK_FORM_COMPLETED', 'CALL_BOOKED',
        'OFFER_PRESENTED', 'CLOSED_WON', 'CLOSED_LOST', 'NURTURE'
      ])
    });

    const { status } = schema.parse(req.body);

    const contact = await prisma.contact.update({
      where: { id: req.params.id },
      data: {
        status,
        previousStatus: prisma.contact.fields.status,
        statusChangedAt: new Date(),
        lastActivityAt: new Date()
      }
    });

    await prisma.activity.create({
      data: {
        contactId: contact.id,
        type: 'STATUS_CHANGE',
        description: `Status changed to ${status}`,
        metadata: { previousStatus: contact.previousStatus }
      }
    });

    res.json(contact);
  } catch (error) {
    res.status(400).json({ error: 'Invalid status update' });
  }
});

export default router;
EOF

cat > apps/api/src/routes/deals.ts << 'EOF'
import { Router } from 'express';
import { prisma } from '../index';

const router = Router();

router.get('/', async (req, res) => {
  try {
    const deals = await prisma.deal.findMany({
      include: {
        contact: { select: { fullName: true, email: true } },
        owner: { select: { fullName: true } }
      },
      orderBy: { createdAt: 'desc' }
    });
    res.json(deals);
  } catch (error) {
    res.status(500).json({ error: 'Failed to fetch deals' });
  }
});

export default router;
EOF

cat > apps/api/src/routes/tasks.ts << 'EOF'
import { Router } from 'express';
import { prisma } from '../index';

const router = Router();

router.get('/', async (req, res) => {
  try {
    const tasks = await prisma.task.findMany({
      include: {
        contact: { select: { fullName: true } },
        assignee: { select: { fullName: true } }
      },
      orderBy: { dueDate: 'asc' }
    });
    res.json(tasks);
  } catch (error) {
    res.status(500).json({ error: 'Failed to fetch tasks' });
  }
});

export default router;
EOF

cat > apps/api/src/routes/reports.ts << 'EOF'
import { Router } from 'express';
import { prisma } from '../index';

const router = Router();

router.get('/dashboard', async (req, res) => {
  try {
    const today = new Date();
    today.setHours(0, 0, 0, 0);

    const [
      newLeadsToday,
      totalContacts,
      dealsWon,
      totalRevenue,
      pipelineData
    ] = await Promise.all([
      prisma.contact.count({ where: { createdAt: { gte: today } } }),
      prisma.contact.count(),
      prisma.deal.count({ where: { stage: 'CLOSED_WON' } }),
      prisma.deal.aggregate({
        where: { stage: 'CLOSED_WON' },
        _sum: { value: true }
      }),
      prisma.contact.groupBy({
        by: ['status'],
        _count: true
      })
    ]);

    const pipeline = [
      { stage: 'NEW', count: 0 },
      { stage: 'CONTACTED', count: 0 },
      { stage: 'WEBINAR_REGISTERED', count: 0 },
      { stage: 'WEBINAR_ATTENDED', count: 0 },
      { stage: 'RISK_FORM_SENT', count: 0 },
      { stage: 'RISK_FORM_COMPLETED', count: 0 },
      { stage: 'CALL_BOOKED', count: 0 },
      { stage: 'OFFER_PRESENTED', count: 0 },
      { stage: 'CLOSED_WON', count: 0 },
      { stage: 'CLOSED_LOST', count: 0 }
    ];

    pipelineData.forEach(p => {
      const item = pipeline.find(i => i.stage === p.status);
      if (item) item.count = p._count;
    });

    res.json({
      newLeadsToday,
      totalContacts,
      dealsWon,
      monthlyRevenue: totalRevenue._sum.value || 0,
      pipelineData: pipeline,
      webinarAttendanceRate: 65,
      formCompletionRate: 42
    });
  } catch (error) {
    res.status(500).json({ error: 'Failed to fetch dashboard data' });
  }
});

export default router;
EOF

cat > apps/api/src/routes/admin.ts << 'EOF'
import { Router } from 'express';
import { prisma, redis } from '../index';

const router = Router();

router.get('/costs', async (req, res) => {
  try {
    const dbStats = await prisma.$queryRaw`
      SELECT pg_database_size(current_database()) as size
    `;

    const redisInfo = await redis.info();
    const keyspaceHits = parseInt(redisInfo.match(/keyspace_hits:(\d+)/)?.[1] || '0');
    const keyspaceMisses = parseInt(redisInfo.match(/keyspace_misses:(\d+)/)?.[1] || '0');

    const emailsThisMonth = await prisma.emailLog.count({
      where: {
        createdAt: { gte: new Date(Date.now() - 30 * 24 * 60 * 60 * 1000) }
      }
    });

    const dbSizeMB = Math.round((dbStats[0] as any).size / 1024 / 1024);

    res.json({
      database: {
        provider: 'Supabase',
        plan: 'Free Tier',
        storageUsed: dbSizeMB,
        storageLimit: 500,
        cost: 0,
        projectedCost: dbSizeMB > 400 ? 25 : 0
      },
      redis: {
        provider: 'Upstash',
        plan: 'Free Tier',
        requestsToday: keyspaceHits + keyspaceMisses,
        requestsLimit: 10000,
        cost: 0
      },
      hosting: {
        provider: 'Render.com',
        plan: 'Free Tier',
        cost: 0
      },
      email: {
        provider: 'SendGrid',
        plan: emailsThisMonth > 100 ? 'Essentials' : 'Free',
        sentThisMonth: emailsThisMonth,
        limit: 100,
        cost: emailsThisMonth > 100 ? 15 : 0
      },
      upgradeTriggers: {
        database: dbSizeMB > 400,
        redis: (keyspaceHits + keyspaceMisses) > 8000,
        hosting: false,
        email: emailsThisMonth > 80
      },
      recommendations: dbSizeMB > 300 ? ['Database approaching limit - consider archiving old data'] : []
    });
  } catch (error) {
    res.status(500).json({ error: 'Failed to fetch cost metrics' });
  }
});

export default router;
EOF

cat > apps/api/src/middleware/auth.ts << 'EOF'
import { Request, Response, NextFunction } from 'express';
import jwt from 'jsonwebtoken';

export const authenticate = (req: Request, res: Response, next: NextFunction) => {
  try {
    const token = req.headers.authorization?.replace('Bearer ', '');
    if (!token) return res.status(401).json({ error: 'No token provided' });

    const decoded = jwt.verify(token, process.env.JWT_SECRET!) as any;
    (req as any).user = decoded;
    next();
  } catch (error) {
    res.status(401).json({ error: 'Invalid token' });
  }
};

export const requireRole = (...roles: string[]) => {
  return (req: Request, res: Response, next: NextFunction) => {
    const user = (req as any).user;
    if (!user || !roles.includes(user.role)) {
      return res.status(403).json({ error: 'Insufficient permissions' });
    }
    next();
  };
};
EOF

mkdir -p apps/api/src/lib
cat > apps/api/src/lib/clients.ts << 'EOF'
export { prisma, redis, emailQueue, automationQueue } from '../index';
EOF

mkdir -p apps/api/src/workers
cat > apps/api/src/workers/index.ts << 'EOF'
import { Worker } from 'bullmq';
import IORedis from 'ioredis';
import dotenv from 'dotenv';
import path from 'path';

dotenv.config({ path: path.join(__dirname, '../../../../.env') });

const redis = new IORedis(process.env.REDIS_URL || 'redis://localhost:6379');

const emailWorker = new Worker('emails', async (job) => {
  console.log('Processing email job:', job.id);
  // Email processing logic here
}, { connection: redis });

const automationWorker = new Worker('automations', async (job) => {
  console.log('Processing automation job:', job.id);
  // Automation logic here
}, { connection: redis });

console.log('🎯 Workers started');

process.on('SIGTERM', async () => {
  await redis.quit();
  process.exit(0);
});
EOF

success "Backend API created"

# =============================================================================
# STEP 6: Create Frontend (condensed version)
# =============================================================================
progress "Creating Frontend Application"

cat > apps/web/package.json << 'EOF'
{
  "name": "@apps/web",
  "version": "1.0.0",
  "private": true,
  "scripts": {
    "dev": "next dev",
    "build": "next build",
    "start": "next start",
    "lint": "next lint"
  },
  "dependencies": {
    "next": "14.0.4",
    "react": "^18.2.0",
    "react-dom": "^18.2.0",
    "@tanstack/react-query": "^5.17.0",
    "@hello-pangea/dnd": "^16.5.0",
    "axios": "^1.6.2",
    "zustand": "^4.4.7",
    "date-fns": "^3.0.6",
    "recharts": "^2.10.3",
    "lucide-react": "^0.303.0",
    "clsx": "^2.0.0",
    "tailwind-merge": "^2.2.0"
  },
  "devDependencies": {
    "@types/node": "^20",
    "@types/react": "^18",
    "@types/react-dom": "^18",
    "autoprefixer": "^10.0.1",
    "eslint": "^8",
    "eslint-config-next": "14.0.4",
    "postcss": "^8",
    "tailwindcss": "^3.3.0",
    "typescript": "^5"
  }
}
EOF

cat > apps/web/next.config.js << 'EOF'
/** @type {import('next').NextConfig} */
const nextConfig = {
  experimental: {
    appDir: true,
  },
  async rewrites() {
    return [
      {
        source: '/api/:path*',
        destination: `${process.env.NEXT_PUBLIC_API_URL}/api/:path*` || 'http://localhost:3001/api/:path*',
      },
    ];
  },
};

module.exports = nextConfig;
EOF

cat > apps/web/tailwind.config.ts << 'EOF'
import type { Config } from 'tailwindcss';

const config: Config = {
  content: [
    './pages/**/*.{js,ts,jsx,tsx,mdx}',
    './components/**/*.{js,ts,jsx,tsx,mdx}',
    './app/**/*.{js,ts,jsx,tsx,mdx}',
  ],
  theme: {
    extend: {
      colors: {
        primary: {
          50: '#eff6ff',
          100: '#dbeafe',
          500: '#3b82f6',
          600: '#2563eb',
          700: '#1d4ed8',
        },
      },
    },
  },
  plugins: [],
};

export default config;
EOF

cat > apps/web/postcss.config.js << 'EOF'
module.exports = {
  plugins: {
    tailwindcss: {},
    autoprefixer: {},
  },
};
EOF

cat > apps/web/tsconfig.json << 'EOF'
{
  "compilerOptions": {
    "lib": ["dom", "dom.iterable", "esnext"],
    "allowJs": true,
    "skipLibCheck": true,
    "strict": true,
    "noEmit": true,
    "esModuleInterop": true,
    "module": "esnext",
    "moduleResolution": "bundler",
    "resolveJsonModule": true,
    "isolatedModules": true,
    "jsx": "preserve",
    "incremental": true,
    "plugins": [
      {
        "name": "next"
      }
    ],
    "paths": {
      "@/*": ["./*"]
    }
  },
  "include": ["next-env.d.ts", "**/*.ts", "**/*.tsx", ".next/types/**/*.ts"],
  "exclude": ["node_modules"]
}
EOF

cat > apps/web/app/globals.css << 'EOF'
@tailwind base;
@tailwind components;
@tailwind utilities;

@layer base {
  html {
    @apply antialiased;
  }
  body {
    @apply bg-gray-50 text-gray-900;
  }
}

@layer components {
  .btn {
    @apply inline-flex items-center justify-center rounded-lg px-4 py-2 text-sm font-medium transition-colors focus:outline-none focus:ring-2 focus:ring-offset-2;
  }
  .btn-primary {
    @apply btn bg-blue-600 text-white hover:bg-blue-700 focus:ring-blue-500;
  }
  .btn-secondary {
    @apply btn bg-white text-gray-700 border border-gray-300 hover:bg-gray-50 focus:ring-blue-500;
  }
}
EOF

cat > apps/web/app/layout.tsx << 'EOF'
import type { Metadata } from 'next';
import { Inter } from 'next/font/google';
import './globals.css';
import { Providers } from './providers';

const inter = Inter({ subsets: ['latin'] });

export const metadata: Metadata = {
  title: 'DRTP CRM',
  description: 'Dr Take Profit CRM System',
};

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html lang="en">
      <body className={inter.className}>
        <Providers>{children}</Providers>
      </body>
    </html>
  );
}
EOF

cat > apps/web/app/providers.tsx << 'EOF'
'use client';

import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { useState } from 'react';

export function Providers({ children }: { children: React.ReactNode }) {
  const [queryClient] = useState(() => new QueryClient({
    defaultOptions: {
      queries: {
        staleTime: 5000,
        refetchOnWindowFocus: false,
      },
    },
  }));

  return (
    <QueryClientProvider client={queryClient}>
      {children}
    </QueryClientProvider>
  );
}
EOF

cat > apps/web/app/(dashboard)/layout.tsx << 'EOF'
import { Sidebar } from '@/components/layout/Sidebar';
import { Header } from '@/components/layout/Header';

export default function DashboardLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <div className="flex h-screen bg-gray-50">
      <Sidebar />
      <div className="flex-1 flex flex-col overflow-hidden">
        <Header />
        <main className="flex-1 overflow-y-auto p-6">
          {children}
        </main>
      </div>
    </div>
  );
}
EOF

cat > apps/web/app/(dashboard)/page.tsx << 'EOF'
'use client';

import { useQuery } from '@tanstack/react-query';
import { api } from '@/lib/api';
import { StatsCard } from '@/components/dashboard/StatsCard';
import { PipelineChart } from '@/components/dashboard/PipelineChart';
import { AlertCircle, TrendingUp, Users, DollarSign } from 'lucide-react';

export default function Dashboard() {
  const { data: stats, isLoading } = useQuery({
    queryKey: ['dashboard-stats'],
    queryFn: async () => {
      const { data } = await api.get('/reports/dashboard');
      return data;
    },
    refetchInterval: 30000,
  });

  if (isLoading) {
    return <div className="flex items-center justify-center h-full">Loading...</div>;
  }

  return (
    <div className="space-y-6">
      <div className="flex justify-between items-center">
        <h1 className="text-3xl font-bold text-gray-900">Dashboard</h1>
        <div className="flex items-center gap-2 text-sm text-gray-500">
          <AlertCircle className="w-4 h-4" />
          Last updated: {new Date().toLocaleTimeString()}
        </div>
      </div>

      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-6">
        <StatsCard
          title="New Leads Today"
          value={stats?.newLeadsToday || 0}
          icon={Users}
          color="blue"
        />
        <StatsCard
          title="Webinar Attendance"
          value={`${stats?.webinarAttendanceRate || 0}%`}
          icon={TrendingUp}
          color="green"
        />
        <StatsCard
          title="Risk Form Completion"
          value={`${stats?.formCompletionRate || 0}%`}
          icon={AlertCircle}
          color="purple"
        />
        <StatsCard
          title="Revenue This Month"
          value={`€${stats?.monthlyRevenue?.toLocaleString() || 0}`}
          icon={DollarSign}
          color="yellow"
        />
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
        <div className="lg:col-span-2 bg-white rounded-lg shadow p-6">
          <h2 className="text-lg font-semibold mb-4">Pipeline Overview</h2>
          <PipelineChart data={stats?.pipelineData || []} />
        </div>
        <div className="bg-white rounded-lg shadow p-6">
          <h2 className="text-lg font-semibold mb-4">Recent Activity</h2>
          <p className="text-gray-500 text-sm">Activity feed coming soon...</p>
        </div>
      </div>
    </div>
  );
}
EOF

# Create essential components (simplified)
mkdir -p apps/web/components/dashboard
cat > apps/web/components/dashboard/StatsCard.tsx << 'EOF'
import { LucideIcon } from 'lucide-react';
import { cn } from '@/lib/utils';

interface StatsCardProps {
  title: string;
  value: string | number;
  icon: LucideIcon;
  color: 'blue' | 'green' | 'purple' | 'yellow';
}

const colorClasses = {
  blue: 'bg-blue-50 text-blue-600',
  green: 'bg-green-50 text-green-600',
  purple: 'bg-purple-50 text-purple-600',
  yellow: 'bg-yellow-50 text-yellow-600',
};

export function StatsCard({ title, value, icon: Icon, color }: StatsCardProps) {
  return (
    <div className="bg-white rounded-lg shadow p-6">
      <div className="flex items-center justify-between">
        <div>
          <p className="text-gray-500 text-sm font-medium">{title}</p>
          <p className="text-2xl font-bold text-gray-900 mt-1">{value}</p>
        </div>
        <div className={cn('p-3 rounded-lg', colorClasses[color])}>
          <Icon className="w-6 h-6" />
        </div>
      </div>
    </div>
  );
}
EOF

cat > apps/web/components/dashboard/PipelineChart.tsx << 'EOF'
'use client';

import { BarChart, Bar, XAxis, YAxis, CartesianGrid, Tooltip, ResponsiveContainer } from 'recharts';

interface PipelineData {
  stage: string;
  count: number;
}

export function PipelineChart({ data }: { data: PipelineData[] }) {
  return (
    <div className="h-64">
      <ResponsiveContainer width="100%" height="100%">
        <BarChart data={data}>
          <CartesianGrid strokeDasharray="3 3" />
          <XAxis 
            dataKey="stage" 
            tick={{ fontSize: 12 }}
            interval={0}
            angle={-45}
            textAnchor="end"
            height={80}
          />
          <YAxis />
          <Tooltip />
          <Bar dataKey="count" fill="#3B82F6" radius={[4, 4, 0, 0]} />
        </BarChart>
      </ResponsiveContainer>
    </div>
  );
}
EOF

mkdir -p apps/web/components/layout
cat > apps/web/components/layout/Sidebar.tsx << 'EOF'
'use client';

import Link from 'next/link';
import { usePathname } from 'next/navigation';
import { 
  LayoutDashboard, 
  Users, 
  Target, 
  CheckSquare, 
  BarChart3, 
  Settings,
  Phone,
  DollarSign
} from 'lucide-react';
import { cn } from '@/lib/utils';

const navigation = [
  { name: 'Dashboard', href: '/', icon: LayoutDashboard },
  { name: 'Contacts', href: '/contacts', icon: Users },
  { name: 'Deals', href: '/deals', icon: Target },
  { name: 'Tasks', href: '/tasks', icon: CheckSquare },
  { name: 'Reports', href: '/reports', icon: BarChart3 },
  { name: 'Costs', href: '/admin/costs', icon: DollarSign },
  { name: 'Settings', href: '/settings', icon: Settings },
];

export function Sidebar() {
  const pathname = usePathname();

  return (
    <div className="w-64 bg-white border-r border-gray-200 flex flex-col">
      <div className="p-6 border-b border-gray-200">
        <div className="flex items-center gap-3">
          <div className="w-10 h-10 bg-blue-600 rounded-lg flex items-center justify-center">
            <Phone className="w-6 h-6 text-white" />
          </div>
          <div>
            <h1 className="font-bold text-lg text-gray-900">DRTP CRM</h1>
            <p className="text-xs text-gray-500">Trading Education</p>
          </div>
        </div>
      </div>

      <nav className="flex-1 p-4 space-y-1">
        {navigation.map((item) => {
          const isActive = pathname === item.href || pathname?.startsWith(`${item.href}/`);
          return (
            <Link
              key={item.name}
              href={item.href}
              className={cn(
                'flex items-center gap-3 px-3 py-2 rounded-lg text-sm font-medium transition-colors',
                isActive 
                  ? 'bg-blue-50 text-blue-700' 
                  : 'text-gray-700 hover:bg-gray-50'
              )}
            >
              <item.icon className={cn('w-5 h-5', isActive ? 'text-blue-600' : 'text-gray-400')} />
              {item.name}
            </Link>
          );
        })}
      </nav>

      <div className="p-4 border-t border-gray-200">
        <div className="flex items-center gap-3">
          <div className="w-8 h-8 rounded-full bg-gray-200 flex items-center justify-center text-sm font-medium text-gray-600">
            A
          </div>
          <div className="flex-1 min-w-0">
            <p className="text-sm font-medium text-gray-900 truncate">Admin User</p>
            <p className="text-xs text-gray-500 truncate">admin@dr-take-profit.com</p>
          </div>
        </div>
      </div>
    </div>
  );
}
EOF

cat > apps/web/components/layout/Header.tsx << 'EOF'
'use client';

import { Bell, Search } from 'lucide-react';
import { Input } from '@/components/ui/Input';

export function Header() {
  return (
    <header className="bg-white border-b border-gray-200 px-6 py-4">
      <div className="flex items-center justify-between">
        <div className="flex items-center gap-4 flex-1">
          <div className="relative max-w-md w-full">
            <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-gray-400" />
            <Input 
              placeholder="Search..." 
              className="pl-10 w-full"
            />
          </div>
        </div>
        
        <div className="flex items-center gap-4">
          <button className="relative p-2 text-gray-400 hover:text-gray-600">
            <Bell className="w-5 h-5" />
            <span className="absolute top-1 right-1 w-2 h-2 bg-red-500 rounded-full"></span>
          </button>
        </div>
      </div>
    </header>
  );
}
EOF

mkdir -p apps/web/components/ui
cat > apps/web/components/ui/Button.tsx << 'EOF'
import { ButtonHTMLAttributes, forwardRef } from 'react';
import { cn } from '@/lib/utils';

interface ButtonProps extends ButtonHTMLAttributes<HTMLButtonElement> {
  variant?: 'primary' | 'secondary' | 'outline' | 'ghost';
  size?: 'sm' | 'md' | 'lg';
}

export const Button = forwardRef<HTMLButtonElement, ButtonProps>(
  ({ className, variant = 'primary', size = 'md', ...props }, ref) => {
    return (
      <button
        ref={ref}
        className={cn(
          'inline-flex items-center justify-center rounded-lg font-medium transition-colors focus:outline-none focus:ring-2 focus:ring-offset-2 disabled:opacity-50 disabled:pointer-events-none',
          {
            'bg-blue-600 text-white hover:bg-blue-700 focus:ring-blue-500': variant === 'primary',
            'bg-white text-gray-700 border border-gray-300 hover:bg-gray-50 focus:ring-blue-500': variant === 'secondary',
            'border border-gray-300 hover:bg-gray-50 focus:ring-blue-500': variant === 'outline',
            'hover:bg-gray-100 focus:ring-gray-500': variant === 'ghost',
            'px-3 py-1.5 text-sm': size === 'sm',
            'px-4 py-2 text-sm': size === 'md',
            'px-6 py-3 text-base': size === 'lg',
          },
          className
        )}
        {...props}
      />
    );
  }
);

Button.displayName = 'Button';
EOF

cat > apps/web/components/ui/Input.tsx << 'EOF'
import { InputHTMLAttributes, forwardRef } from 'react';
import { cn } from '@/lib/utils';

export const Input = forwardRef<HTMLInputElement, InputHTMLAttributes<HTMLInputElement>>(
  ({ className, ...props }, ref) => {
    return (
      <input
        ref={ref}
        className={cn(
          'flex w-full rounded-lg border border-gray-300 bg-white px-3 py-2 text-sm placeholder:text-gray-400 focus:outline-none focus:ring-2 focus:ring-blue-500 focus:border-transparent disabled:cursor-not-allowed disabled:opacity-50',
          className
        )}
        {...props}
      />
    );
  }
);

Input.displayName = 'Input';
EOF

mkdir -p apps/web/lib
cat > apps/web/lib/api.ts << 'EOF'
import axios from 'axios';

const getBaseUrl = () => {
  if (process.env.NEXT_PUBLIC_API_URL) {
    return process.env.NEXT_PUBLIC_API_URL;
  }
  if (typeof window !== 'undefined') {
    const saved = localStorage.getItem('CRM_API_URL');
    if (saved) return saved;
  }
  return 'http://localhost:3001';
};

export const api = axios.create({
  baseURL: getBaseUrl(),
  headers: {
    'Content-Type': 'application/json',
  },
});

api.interceptors.request.use((config) => {
  if (typeof window !== 'undefined') {
    const token = localStorage.getItem('token');
    if (token) {
      config.headers.Authorization = `Bearer ${token}`;
    }
  }
  return config;
});

api.interceptors.response.use(
  (response) => response,
  (error) => {
    if (error.response?.status === 401) {
      if (typeof window !== 'undefined') {
        localStorage.removeItem('token');
        window.location.href = '/login';
      }
    }
    return Promise.reject(error);
  }
);
EOF

cat > apps/web/lib/utils.ts << 'EOF'
import { type ClassValue, clsx } from 'clsx';
import { twMerge } from 'tailwind-merge';

export function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs));
}
EOF

success "Frontend application created"

# =============================================================================
# STEP 7: Create Deployment Configuration
# =============================================================================
progress "Creating Deployment Configuration for $PROJECT_NAME"

cat > render.yaml << EOF
services:
  - type: web
    name: $PROJECT_NAME-api
    runtime: node
    region: frankfurt
    plan: free
    rootDir: apps/api
    buildCommand: npm install && npm run build
    startCommand: npm start
    healthCheckPath: /health
    envVars:
      - key: NODE_ENV
        value: production
      - key: PORT
        value: 10000
      - key: JWT_SECRET
        generateValue: true
      - key: DATABASE_URL
        sync: false
      - key: REDIS_URL
        sync: false
      - key: FRONTEND_URL
        sync: false
      - key: META_WEBHOOK_VERIFY_TOKEN
        generateValue: true

  - type: worker
    name: $PROJECT_NAME-worker
    runtime: node
    region: frankfurt
    plan: free
    rootDir: apps/api
    buildCommand: npm install && npm run build
    startCommand: npm run worker
    envVars:
      - key: NODE_ENV
        value: production
      - key: DATABASE_URL
        fromService:
          type: web
          name: $PROJECT_NAME-api
          envVarKey: DATABASE_URL
      - key: REDIS_URL
        fromService:
          type: web
          name: $PROJECT_NAME-api
          envVarKey: REDIS_URL
      - key: JWT_SECRET
        fromService:
          type: web
          name: $PROJECT_NAME-api
          envVarKey: JWT_SECRET

databases:
  - name: $PROJECT_NAME-db
    plan: free
    ipAllowList: []

version: "1"
EOF

cat > vercel.json << 'EOF'
{
  "version": 2,
  "buildCommand": "cd apps/web && npm run build",
  "outputDirectory": "apps/web/.next",
  "framework": "nextjs",
  "rewrites": [
    {
      "source": "/api/:path*",
      "destination": "https://your-api-url.onrender.com/api/:path*"
    }
  ],
  "env": {
    "NEXT_PUBLIC_API_URL": "@api_url"
  }
}
EOF

cat > apps/api/Dockerfile << 'EOF'
FROM node:18-alpine AS base

RUN apk add --no-cache libc6-compat openssl

WORKDIR /app

COPY package*.json ./
COPY apps/api/package*.json ./apps/api/
COPY packages/database/package*.json ./packages/database/

RUN npm ci --only=production

COPY . .

RUN cd packages/database && npx prisma generate
RUN cd apps/api && npm run build

FROM node:18-alpine AS runner

WORKDIR /app

ENV NODE_ENV=production
ENV PORT=10000

RUN apk add --no-cache openssl

COPY --from=base /app/apps/api/dist ./dist
COPY --from=base /app/apps/api/node_modules ./node_modules
COPY --from=base /app/packages ./packages
COPY --from=base /app/node_modules ./node_modules
COPY --from=base /app/package.json ./package.json

RUN addgroup --system --gid 1001 nodejs
RUN adduser --system --uid 1001 expressjs
USER expressjs

EXPOSE 10000

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries-3 \
  CMD node -e "require('http').get('http://localhost:10000/health', (r) => r.statusCode === 200 ? process.exit(0) : process.exit(1))"

CMD ["node", "dist/index.js"]
EOF

success "Deployment configuration created"

# =============================================================================
# STEP 8: Create Documentation
# =============================================================================
progress "Creating Documentation"

cat > README.md << EOF
# DRTP CRM

Dr Take Profit Trading Education CRM - Free Tier Deployment

## 🚀 One-Click Deploy

### Backend (Render.com)
[![Deploy to Render](https://render.com/images/deploy-to-render-button.svg)](https://render.com/deploy)

### Frontend (Vercel)
[![Deploy with Vercel](https://vercel.com/button)](https://vercel.com/new/clone?repository-url=https://github.com/yourusername/$PROJECT_NAME)

## 💰 Free Tier Includes

- **Database**: 500MB (Supabase)
- **Cache**: 10K requests/day (Upstash)
- **Hosting**: Always free (Render.com)
- **Frontend**: Unlimited (Vercel)
- **Total Cost**: €0/month

## 📋 Quick Start

\`\`\`bash
# 1. Clone repository
git clone https://github.com/yourusername/$PROJECT_NAME.git
cd $PROJECT_NAME

# 2. Install dependencies
npm install

# 3. Start local development
docker-compose up -d
npm run db:migrate
npm run dev
\`\`\`

## 🔧 Environment Variables

| Variable | Description | Required |
|----------|-------------|----------|
| \`DATABASE_URL\` | PostgreSQL connection | Yes |
| \`REDIS_URL\` | Redis connection | Yes |
| \`JWT_SECRET\` | JWT signing key | Auto-generated |
| \`NEXT_PUBLIC_API_URL\` | Backend API URL | Yes |
| \`META_WEBHOOK_VERIFY_TOKEN\` | Meta webhook verification | Auto-generated |

## 📚 Documentation

- [Deployment Guide](./DEPLOYMENT_CHECKLIST.md)

## 📄 License

MIT License
EOF

success "Documentation created"

# =============================================================================
# STEP 9: Initialize Git Repository
# =============================================================================
progress "Initializing Git Repository"

git init
git add .
git commit -m "Initial commit: DRTP CRM v1.0"

success "Git repository initialized"

# =============================================================================
# STEP 10: Final Instructions
# =============================================================================
progress "Setup Complete!"

echo ""
echo "🎉 $PROJECT_NAME has been created successfully!"
echo ""
echo "📁 Project location: $(pwd)"
echo ""
echo "🚀 NEXT STEPS:"
echo ""
echo "1. Create GitHub repository:"
echo "   - Go to https://github.com/new"
echo "   - Name: $PROJECT_NAME"
echo "   - Click Create"
echo ""
echo "2. Push to GitHub:"
echo "   git remote add origin https://github.com/YOUR_USERNAME/$PROJECT_NAME.git"
echo "   git branch -M main"
echo "   git push -u origin main"
echo ""
echo "3. Set up Supabase (Database):"
echo "   - Go to https://supabase.com"
echo "   - Create new project (Free tier)"
echo "   - Copy connection string"
echo ""
echo "4. Set up Upstash (Redis):"
echo "   - Go to https://upstash.com"
echo "   - Create Redis database (Free tier)"
echo "   - Copy Redis URL"
echo ""
echo "5. Deploy to Render.com:"
echo "   - Go to https://render.com"
echo "   - Click 'New Blueprint Instance'"
echo "   - Connect your GitHub repo: $PROJECT_NAME"
echo "   - Add environment variables"
echo ""
echo "6. Deploy to Vercel:"
echo "   - Go to https://vercel.com"
echo "   - Import your GitHub repo: $PROJECT_NAME"
echo "   - Set framework to Next.js"
echo "   - Set root directory to apps/web"
echo ""
echo "💰 Total Monthly Cost: €0 (Free tier)"
echo ""
echo "📊 Monitor costs at: /admin/costs after deployment"
echo ""

cat > DEPLOYMENT_CHECKLIST.md << EOF
# Deployment Checklist for $PROJECT_NAME

## Pre-Deployment
- [ ] GitHub repository created: $PROJECT_NAME
- [ ] Code pushed to GitHub
- [ ] Supabase account created
- [ ] Upstash account created
- [ ] Render.com account created
- [ ] Vercel account created

## Database Setup
- [ ] Supabase project created
- [ ] Database password saved
- [ ] Connection string copied

## Redis Setup
- [ ] Upstash database created
- [ ] Redis URL copied

## Backend Deployment (Render)
- [ ] Blueprint instance created
- [ ] Environment variables configured
- [ ] Service deployed successfully

## Frontend Deployment (Vercel)
- [ ] Project imported from GitHub
- [ ] Build successful

## Meta Integration
- [ ] Meta app created
- [ ] Webhook configured
- [ ] Test lead received

## Post-Deployment
- [ ] Admin user created
- [ ] Login works
- [ ] Cost monitoring accessible
EOF

success "Deployment checklist created"

echo ""
echo -e "${GREEN}✅ All done! Your CRM '$PROJECT_NAME' is ready to deploy.${NC}"
echo ""
