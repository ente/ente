import {
    Box,
    keyframes,
    Link,
    Skeleton,
    Stack,
    styled,
    ToggleButton,
    ToggleButtonGroup,
    Typography,
} from "@mui/material";
import { authDisplayFontFamily } from "ente-accounts/components/auth/styles";
import { FocusVisibleButton } from "ente-base/components/mui/FocusVisibleButton";
import { formattedNumber } from "ente-base/i18n";
import { formattedByteSize } from "ente-gallery/utils/units";
import type {
    Plan,
    PlanPeriod,
    PlansData,
} from "ente-new/photos/services/user-details";
import { t } from "i18next";
import { useCallback, useEffect, useId, useRef, useState } from "react";
import { Trans } from "react-i18next";

const planCardMinHeight = 80;

const lockerProductLink = (
    <Link
        href="https://ente.com/locker"
        target="_blank"
        rel="noreferrer"
        color="inherit"
        underline="always"
    />
);

interface PlanSelectionCardsProps {
    plansData: PlansData | undefined;
    initialPeriod?: PlanPeriod;
    currentPlanID?: string;
    listMaxHeight?: string;
    showLockerAllowance?: boolean;
    freePlanAction?: "continue" | "close";
    onContinueFree?: () => void;
    onContinuePaid: (plan: Plan) => void;
}

export function PlanSelectionCards({
    plansData,
    initialPeriod = "year",
    currentPlanID,
    listMaxHeight,
    showLockerAllowance = false,
    freePlanAction = "continue",
    onContinueFree,
    onContinuePaid,
}: PlanSelectionCardsProps) {
    const planListRef = useRef<HTMLDivElement>(null);
    const [canScrollUp, setCanScrollUp] = useState(false);
    const [canScrollDown, setCanScrollDown] = useState(false);
    const [selectedPeriod, setSelectedPeriod] = useState<PlanPeriod>();
    const period = selectedPeriod ?? initialPeriod;
    const [selectedPlanID, setSelectedPlanID] = useState<string | null>();
    const paidPlans = plansData?.plans.filter(
        (plan) =>
            plan.period === period &&
            plan.id !== "free" &&
            (plan.stripeID || plan.id === currentPlanID),
    );
    const selection =
        selectedPlanID === undefined ? currentPlanID : selectedPlanID;
    const selectedPlan = paidPlans?.find(({ id }) => id === selection);
    const selectedIsCurrent =
        selectedPlan !== undefined && selectedPlan.id === currentPlanID;
    const selectedStorage =
        selectedPlan?.storage ??
        (onContinueFree ? plansData?.freePlan.storage : undefined);
    let continueLabel = t("choose_plan");
    if (selectedIsCurrent) {
        continueLabel = t("plan_current");
    } else if (selectedStorage !== undefined) {
        continueLabel =
            !selectedPlan && freePlanAction === "close"
                ? t("close")
                : t("continue_with_storage_plan", {
                      storage: formattedByteSize(selectedStorage, 0),
                  });
    }

    const updateScrollEdges = useCallback(() => {
        const list = planListRef.current;
        if (!list) return;
        const { scrollTop, scrollHeight, clientHeight } = list;
        setCanScrollUp(scrollTop > 1);
        setCanScrollDown(scrollHeight - clientHeight - scrollTop > 1);
    }, []);

    useEffect(() => {
        const list = planListRef.current;
        if (!list) return;
        const observer = new ResizeObserver(updateScrollEdges);
        observer.observe(list);
        for (const card of list.children) observer.observe(card);
        updateScrollEdges();
        return () => observer.disconnect();
    }, [period, plansData, updateScrollEdges]);

    return (
        <Stack
            sx={(theme) => ({
                gap: 2,
                minHeight: 0,
                flex: 1,
                "--plan-panel-surface": `var(--auth-ui-content-background, ${theme.vars.palette.background.paper2})`,
                "--plan-card-stroke": "var(--auth-ui-stroke, #e0e0e0)",
                ...theme.applyStyles("dark", {
                    "--plan-card-stroke": "var(--auth-ui-stroke, #3e3e3e)",
                }),
            })}
        >
            <BillingPeriodToggle
                exclusive
                fullWidth
                value={period}
                aria-label={t("plan_billing_period")}
                onChange={(_, newPeriod: PlanPeriod | null) => {
                    if (!newPeriod) return;
                    setSelectedPeriod(newPeriod);
                    setSelectedPlanID(undefined);
                    planListRef.current?.scrollTo({ top: 0 });
                }}
            >
                <ToggleButton value="month">{t("monthly")}</ToggleButton>
                <ToggleButton value="year">{t("yearly")}</ToggleButton>
            </BillingPeriodToggle>
            <PlanListViewport
                sx={{ maxHeight: listMaxHeight }}
                data-scroll-up={canScrollUp}
                data-scroll-down={canScrollDown}
            >
                <Stack
                    data-selection-made={selectedPlanID !== undefined}
                    ref={planListRef}
                    onScroll={updateScrollEdges}
                    role="radiogroup"
                    aria-label={t("choose_plan")}
                    aria-busy={!plansData}
                    sx={{
                        gap: 2.5,
                        minHeight: 0,
                        flex: 1,
                        overflowY: "auto",
                        overscrollBehaviorY: "contain",
                        px: "8px",
                        py: "4px",
                        "& > *": { flexShrink: 0 },
                    }}
                >
                    {plansData ? (
                        <>
                            {onContinueFree && (
                                <PlanSelectionCard
                                    storage={plansData.freePlan.storage}
                                    selected={!selectedPlan}
                                    current={freePlanAction === "continue"}
                                    showLockerAllowance={showLockerAllowance}
                                    onSelect={() => setSelectedPlanID(null)}
                                />
                            )}
                            {paidPlans?.map((plan) => (
                                <PlanSelectionCard
                                    key={plan.id}
                                    storage={plan.storage}
                                    plan={plan}
                                    originalMonthlyPrice={
                                        period === "year"
                                            ? plansData.plans.find(
                                                  (monthlyPlan) =>
                                                      monthlyPlan.period ===
                                                          "month" &&
                                                      monthlyPlan.storage ===
                                                          plan.storage &&
                                                      monthlyPlan.stripeID,
                                              )?.price
                                            : undefined
                                    }
                                    selected={selectedPlan?.id === plan.id}
                                    current={plan.id === currentPlanID}
                                    onSelect={() => setSelectedPlanID(plan.id)}
                                />
                            ))}
                        </>
                    ) : (
                        [0, 1, 2].map((index) => (
                            <Skeleton
                                key={index}
                                variant="rounded"
                                height={planCardMinHeight}
                            />
                        ))
                    )}
                </Stack>
            </PlanListViewport>
            {plansData && (
                <Box sx={{ flexShrink: 0, pb: { xs: 3, sm: 0 } }}>
                    <PlanContinueButton
                        variant="contained"
                        fullWidth
                        disabled={
                            selectedStorage === undefined || selectedIsCurrent
                        }
                        onClick={() =>
                            selectedPlan
                                ? onContinuePaid(selectedPlan)
                                : onContinueFree?.()
                        }
                    >
                        {continueLabel}
                    </PlanContinueButton>
                    {showLockerAllowance && !!paidPlans?.length && (
                        <Typography
                            component="p"
                            variant="small"
                            sx={(theme) => ({
                                mt: 1.5,
                                fontSize: "0.75rem",
                                fontWeight: 400,
                                lineHeight: 1.4,
                                textAlign: "center",
                                color: "text.muted",
                                opacity: 0.9,
                                ...theme.applyStyles("dark", { opacity: 0.66 }),
                            })}
                        >
                            <Trans
                                i18nKey="paid_plans_locker_allowance"
                                values={{ count: 1000 }}
                                components={{ locker: lockerProductLink }}
                            />
                        </Typography>
                    )}
                </Box>
            )}
        </Stack>
    );
}

interface PlanSelectionCardProps {
    storage: number;
    plan?: Plan;
    originalMonthlyPrice?: string;
    selected: boolean;
    current: boolean;
    showLockerAllowance?: boolean;
    onSelect: () => void;
}

function PlanSelectionCard({
    storage,
    plan,
    originalMonthlyPrice,
    selected,
    current,
    showLockerAllowance = false,
    onSelect,
}: PlanSelectionCardProps) {
    const id = useId();
    const [value, unit] = formattedByteSize(storage, 0).split(" ");
    const isPopular = !!plan && /^200gb_(monthly|yearly)/.test(plan.id);
    const yearlyMonthlyPrice =
        plan?.period === "year" ? formatPrice(plan.price, 12) : undefined;
    const showBadge = current || isPopular;
    const descriptions = [
        showLockerAllowance && `${id}-locker`,
        showBadge && `${id}-badge`,
    ].filter(Boolean);

    return (
        <PlanCard data-selected={selected} data-has-badge={showBadge}>
            <input
                type="radio"
                name="subscription-plan"
                checked={selected}
                onChange={onSelect}
                aria-labelledby={`${id}-storage ${id}-price`}
                aria-describedby={descriptions.join(" ") || undefined}
            />
            <Box component="span">
                <Box
                    component="span"
                    id={`${id}-storage`}
                    className="plan-storage"
                >
                    {value} <span>{unit}</span>
                </Box>
                {showLockerAllowance && (
                    <Box
                        component="span"
                        id={`${id}-locker`}
                        className="plan-locker-allowance"
                    >
                        <Trans
                            i18nKey="plan_locker_allowance"
                            values={{ count: 100 }}
                            components={{
                                locker: selected ? lockerProductLink : <span />,
                            }}
                        />
                    </Box>
                )}
            </Box>
            <Box
                component="span"
                id={`${id}-price`}
                sx={{ textAlign: "end", fontWeight: 600 }}
            >
                {plan ? (
                    <>
                        {formatPrice(plan.price) ?? plan.price}
                        <span className="plan-period">
                            /
                            {t(plan.period === "year" ? "year" : "month_short")}
                        </span>
                        {yearlyMonthlyPrice && (
                            <Box
                                component="span"
                                className="plan-monthly-price"
                                sx={{ display: "block" }}
                            >
                                {originalMonthlyPrice && (
                                    <>
                                        <s>
                                            {formatPrice(
                                                originalMonthlyPrice,
                                            ) ?? originalMonthlyPrice}
                                        </s>{" "}
                                        <span aria-hidden="true">→ </span>
                                    </>
                                )}
                                {yearlyMonthlyPrice}/{t("plan_billing_month")}
                            </Box>
                        )}
                    </>
                ) : (
                    t("plan_free")
                )}
            </Box>
            {showBadge && (
                <PlanBadge id={`${id}-badge`} data-current={current}>
                    {t(current ? "plan_current" : "plan_most_popular")}
                </PlanBadge>
            )}
        </PlanCard>
    );
}

function formatPrice(price: string, divisor = 1) {
    const [, prefix, amount, suffix] =
        /^(\D*)(\d+(?:\.\d+)?)(\D*)$/.exec(price) ?? [];
    if (!amount) return undefined;
    const value = Math.round((Number(amount) / divisor) * 100) / 100;
    return `${prefix}${formattedNumber(value)}${suffix}`;
}

const BillingPeriodToggle = styled(ToggleButtonGroup)(({ theme }) => ({
    flexShrink: 0,
    padding: 4,
    gap: 4,
    borderRadius: 35,
    backgroundColor: "var(--auth-ui-fill, #eaeaea)",
    boxShadow: "inset 0 0 0 1px var(--plan-card-stroke)",
    ...theme.applyStyles("dark", { backgroundColor: "#171717" }),
    "& .MuiToggleButtonGroup-grouped": {
        flex: "1 1 0",
        minHeight: 41,
        padding: "6px 12px",
        margin: 0,
        border: 0,
        borderRadius: 35,
        color: theme.vars.palette.text.muted,
        textTransform: "none",
        transition: theme.transitions.create(
            ["background-color", "color", "box-shadow", "translate"],
            { duration: 160, easing: theme.transitions.easing.easeOut },
        ),
        "&:active": { translate: "0 1px" },
        "@media (prefers-reduced-motion: reduce)": {
            transition: "none",
            "&:active": { translate: "none" },
        },
        "&.Mui-selected, &.Mui-selected:hover": {
            backgroundColor: "var(--auth-ui-field, #fff)",
            color: theme.vars.palette.text.primary,
            fontWeight: 650,
            boxShadow: "0 1px 2px rgba(0 0 0 / 0.12)",
            ...theme.applyStyles("dark", {
                backgroundColor: "#383838",
                boxShadow: "0 1px 2px rgba(0 0 0 / 0.3)",
            }),
        },
        "&.Mui-focusVisible": {
            outline: `2px solid ${theme.vars.palette.text.primary}`,
            outlineOffset: -2,
        },
    },
}));

const PlanListViewport = styled("div")({
    position: "relative",
    display: "flex",
    flexDirection: "column",
    flex: 1,
    minHeight: 0,
    marginInline: -8,
    "--plan-edge-depth": "min(36px, 25%)",
    "--plan-top-mask": "black",
    "--plan-bottom-mask": "black",
    '&[data-scroll-up="true"]': { "--plan-top-mask": "transparent" },
    '&[data-scroll-down="true"]': { "--plan-bottom-mask": "transparent" },
    '& > [role="radiogroup"]': {
        maskImage:
            "linear-gradient(to bottom, var(--plan-top-mask) 4px, black var(--plan-edge-depth), black calc(100% - var(--plan-edge-depth)), var(--plan-bottom-mask) calc(100% - 4px))",
    },
    "&::before, &::after": {
        content: '""',
        position: "absolute",
        insetInline: 0,
        zIndex: 1,
        height: "var(--plan-edge-depth)",
        backgroundColor:
            "color-mix(in srgb, var(--plan-panel-surface) 72%, transparent)",
        backdropFilter: "blur(5px)",
        pointerEvents: "none",
        opacity: 0,
        transition: "opacity 120ms ease-out",
        "@media (prefers-reduced-motion: reduce)": { transition: "none" },
    },
    "&::before": {
        top: 0,
        maskImage: "linear-gradient(to bottom, black, transparent)",
    },
    "&::after": {
        bottom: 0,
        maskImage: "linear-gradient(to top, black, transparent)",
    },
    '&[data-scroll-up="true"]::before, &[data-scroll-down="true"]::after': {
        opacity: 1,
    },
});

const planSelectionPop = keyframes({
    "0%": { translate: "0 2px" },
    "60%": { translate: "0 -1px" },
    "100%": { translate: "0 0" },
});

const PlanCard = styled("label")(({ theme }) => ({
    position: "relative",
    display: "grid",
    gridTemplateColumns: "minmax(0, 1fr) auto",
    alignItems: "center",
    columnGap: 12,
    minHeight: planCardMinHeight,
    boxSizing: "border-box",
    padding: "8px 20px",
    border: "3px solid var(--plan-card-stroke)",
    borderRadius: 20,
    color: theme.vars.palette.text.primary,
    "--plan-card-surface": "var(--auth-ui-field, #fff)",
    backgroundColor: "var(--plan-card-surface)",
    cursor: "pointer",
    "--plan-card-side": "8px",
    "--plan-card-base": "11px",
    transition: theme.transitions.create(
        ["background-color", "border-color", "box-shadow", "translate"],
        { duration: 200, easing: theme.transitions.easing.easeOut },
    ),
    ...theme.applyStyles("dark", { "--plan-card-surface": "#212121" }),
    "&:hover": { borderColor: theme.vars.palette.text.muted },
    '&:first-child[data-has-badge="true"]': { marginBlockStart: 22 },
    "&:active:not(:has(a:active))": {
        "--plan-card-side": "5px",
        "--plan-card-base": "7px",
        translate: "0 2px",
        transitionDuration: "90ms",
    },
    "&:has(input:focus-visible)": {
        outline: `2px solid ${theme.vars.palette.text.primary}`,
        outlineOffset: 2,
    },
    "& input": { position: "absolute", width: 1, height: 1, opacity: 0 },
    "& .plan-storage": {
        display: "block",
        fontFamily: authDisplayFontFamily,
        fontWeight: 900,
        fontSize: 36,
        lineHeight: "38px",
        letterSpacing: "-0.04em",
        whiteSpace: "nowrap",
        transition: theme.transitions.create("font-size", {
            duration: 200,
            easing: theme.transitions.easing.easeOut,
        }),
        "& span": {
            fontSize: "0.45em",
            fontWeight: 700,
            letterSpacing: 0,
            lineHeight: 1,
        },
    },
    "& .plan-locker-allowance": {
        display: "block",
        fontSize: "0.75rem",
        lineHeight: "18px",
        color: theme.vars.palette.text.muted,
    },
    "& .plan-period, & .plan-monthly-price": {
        color: theme.vars.palette.text.muted,
        fontSize: "0.75rem",
    },
    "& .plan-monthly-price": { fontSize: "0.625rem" },
    '&[data-selected="true"]': {
        color: "#171717",
        backgroundColor: "var(--auth-ui-primary, #08c225)",
        borderColor: "#46e35e",
        boxShadow:
            "0 var(--plan-card-side) 0 #009b18, 0 var(--plan-card-base) 0 var(--plan-card-surface)",
        "& .plan-storage": {
            fontSize: 42,
            ...theme.applyStyles("dark", { color: "var(--plan-card-surface)" }),
        },
        "& .plan-period, & .plan-monthly-price, & .plan-locker-allowance": {
            color: "inherit",
        },
    },
    "@media (prefers-reduced-motion: no-preference)": {
        '[data-selection-made="true"] &[data-selected="true"]:not(:active)': {
            animation: `${planSelectionPop} 150ms ease-out`,
        },
    },
    "@media (prefers-reduced-motion: reduce)": {
        transition: "none",
        "& .plan-storage": { transition: "none" },
        "&:active:not(:has(a:active))": {
            translate: "none",
            transitionDuration: "0ms",
        },
    },
}));

const PlanContinueButton = styled(FocusVisibleButton)(({ theme }) => ({
    minHeight: 60,
    borderRadius: 20,
    fontFamily: authDisplayFontFamily,
    fontWeight: 700,
    fontSize: 16,
    "--plan-button-rim": "#454545",
    "--plan-button-face": "#000",
    "--plan-button-ink": "#fff",
    ...theme.applyStyles("dark", {
        "--plan-button-rim": "#858585",
        "--plan-button-face": "#fff",
        "--plan-button-ink": "#000",
    }),
    "&:not(.Mui-disabled)": {
        backgroundColor: "var(--plan-button-face)",
        color: "var(--plan-button-ink)",
    },
    boxShadow: "0 4px 0 var(--plan-button-rim)",
    "&:hover": { boxShadow: "0 4px 0 var(--plan-button-rim)" },
    "&.Mui-disabled": { boxShadow: "none" },
    transition: theme.transitions.create(
        ["background-color", "box-shadow", "translate"],
        { duration: 160, easing: theme.transitions.easing.easeOut },
    ),
    "&:active": {
        translate: "0 3px",
        boxShadow: "0 1px 0 var(--plan-button-rim)",
        transitionDuration: "90ms",
    },
    "@media (prefers-reduced-motion: reduce)": {
        transition: "none",
        "&:active": { translate: "none", transitionDuration: "0ms" },
    },
}));

const PlanBadge = styled("span")({
    position: "absolute",
    insetInlineEnd: -4,
    top: -25,
    display: "grid",
    placeItems: "center",
    minWidth: 118,
    minHeight: 38,
    padding: "8px 10px 4px",
    border: "2px solid #171717",
    borderRadius: 13,
    backgroundColor: "#46e35e",
    color: "#171717",
    fontFamily: authDisplayFontFamily,
    fontSize: "0.75rem",
    fontWeight: 700,
    "--plan-badge-highlight": "#7de68d",
    '&[data-current="true"]': {
        backgroundColor: "#ffd525",
        "--plan-badge-highlight": "#ffefad",
    },
    "&::before, &::after": {
        content: '""',
        position: "absolute",
        insetBlockStart: 4,
        insetInlineStart: 6,
        width: 23,
        height: 5,
        backgroundColor: "var(--plan-badge-highlight)",
        borderRadius: 3,
    },
    "&::after": { insetInlineStart: 31, width: 6 },
});
