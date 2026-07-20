'use client';

import Link from 'next/link';
import { useState, type ReactNode } from 'react';

// metadata moved to layout.tsx since this is a client component

type Feature = 'yes' | 'no' | 'partial';

interface Adapter {
  name: string;
  slug: string;
  gem: string;
  type: 'platform' | 'state';
  tagline: string;
  color: string;
  icon: ReactNode;
  official?: boolean;
  features: Record<string, Feature>;
}

function SlackIcon({ size = 22 }: { size?: number }) {
  return (
    <svg viewBox="0 0 16 16" width={size} height={size} fill="#fff">
      <path d="M3.362 10.11c0 .926-.756 1.681-1.681 1.681S0 11.036 0 10.111.756 8.43 1.68 8.43h1.682zm.846 0c0-.924.756-1.68 1.681-1.68s1.681.756 1.681 1.68v4.21c0 .924-.756 1.68-1.68 1.68a1.685 1.685 0 0 1-1.682-1.68zM5.89 3.362c-.926 0-1.682-.756-1.682-1.681S4.964 0 5.89 0s1.68.756 1.68 1.68v1.682zm0 .846c.924 0 1.68.756 1.68 1.681S6.814 7.57 5.89 7.57H1.68C.757 7.57 0 6.814 0 5.89c0-.926.756-1.682 1.68-1.682zm6.749 1.682c0-.926.755-1.682 1.68-1.682S16 4.964 16 5.889s-.756 1.681-1.68 1.681h-1.681zm-.848 0c0 .924-.755 1.68-1.68 1.68A1.685 1.685 0 0 1 8.43 5.89V1.68C8.43.757 9.186 0 10.11 0c.926 0 1.681.756 1.681 1.68zm-1.681 6.748c.926 0 1.682.756 1.682 1.681S11.036 16 10.11 16s-1.681-.756-1.681-1.68v-1.682h1.68zm0-.847c-.924 0-1.68-.755-1.68-1.68s.756-1.681 1.68-1.681h4.21c.924 0 1.68.756 1.68 1.68 0 .926-.756 1.681-1.68 1.681z" />
    </svg>
  );
}

function TeamsIcon({ size = 22 }: { size?: number }) {
  return (
    <svg viewBox="0 0 16 16" width={size} height={size} fill="#fff">
      <path d="M9.186 4.797a2.42 2.42 0 1 0-2.86-2.448h1.178c.929 0 1.682.753 1.682 1.682zm-4.295 7.738h2.613c.929 0 1.682-.753 1.682-1.682V5.58h2.783a.7.7 0 0 1 .682.716v4.294a4.197 4.197 0 0 1-4.093 4.293c-1.618-.04-3-.99-3.667-2.35Zm10.737-9.372a1.674 1.674 0 1 1-3.349 0 1.674 1.674 0 0 1 3.349 0m-2.238 9.488-.12-.002a5.2 5.2 0 0 0 .381-2.07V6.306a1.7 1.7 0 0 0-.15-.725h1.792c.39 0 .707.317.707.707v3.765a2.6 2.6 0 0 1-2.598 2.598z" />
      <path d="M.682 3.349h6.822c.377 0 .682.305.682.682v6.822a.68.68 0 0 1-.682.682H.682A.68.68 0 0 1 0 10.853V4.03c0-.377.305-.682.682-.682Zm5.206 2.596v-.72h-3.59v.72h1.357V9.66h.87V5.945z" />
    </svg>
  );
}

function GChatIcon({ size = 22 }: { size?: number }) {
  return (
    <svg viewBox="0 0 24 24" width={size} height={size} fill="#fff">
      <path d="M1.637 0C.733 0 0 .733 0 1.637v16.5c0 .904.733 1.636 1.637 1.636h3.955v3.323c0 .804.97 1.207 1.539.638l3.963-3.96h11.27c.903 0 1.636-.733 1.636-1.637V5.592L18.408 0Zm3.955 5.592h12.816v8.59H8.455l-2.863 2.863Z" />
    </svg>
  );
}

function MattermostIcon({ size = 22 }: { size?: number }) {
  return (
    <svg viewBox="0 0 24 24" width={size} height={size} fill="#fff">
      <path d="M12.081 0C7.048-.034 2.339 3.125.637 8.153c-2.125 6.276 1.24 13.086 7.516 15.21 6.276 2.125 13.086-1.24 15.21-7.516 1.727-5.1-.172-10.552-4.311-13.557l.126 2.547c2.065 2.282 2.88 5.512 1.852 8.549-1.534 4.532-6.594 6.915-11.3 5.321-4.708-1.593-7.28-6.559-5.745-11.092 1.031-3.046 3.655-5.121 6.694-5.67l1.642-1.94A4.87 4.87 0 0 0 12.08 0zm3.528 1.094a.284.284 0 0 0-.123.024l-.004.001a.33.33 0 0 0-.109.071c-.145.142-.657.828-.657.828L13.6 3.4l-1.3 1.585-2.232 2.776s-1.024 1.278-.798 2.851c.226 1.574 1.396 2.34 2.304 2.648.907.307 2.302.408 3.438-.704 1.135-1.112 1.098-2.75 1.098-2.75l-.087-3.56-.07-2.05-.047-1.775s.01-.856-.02-1.057a.33.33 0 0 0-.035-.107l-.006-.012-.007-.011a.277.277 0 0 0-.229-.14z" />
    </svg>
  );
}

function DiscordIcon({ size = 22 }: { size?: number }) {
  return (
    <svg viewBox="0 0 24 24" width={size} height={size} fill="#fff">
      <path d="M20.317 4.37a19.791 19.791 0 0 0-4.885-1.515.074.074 0 0 0-.079.037c-.21.375-.444.864-.608 1.25a18.27 18.27 0 0 0-5.487 0 12.64 12.64 0 0 0-.617-1.25.077.077 0 0 0-.079-.037A19.736 19.736 0 0 0 3.677 4.37a.07.07 0 0 0-.032.027C.533 9.046-.32 13.58.099 18.057a.082.082 0 0 0 .031.057 19.9 19.9 0 0 0 5.993 3.03.078.078 0 0 0 .084-.028c.462-.63.874-1.295 1.226-1.994a.076.076 0 0 0-.041-.106 13.107 13.107 0 0 1-1.872-.892.077.077 0 0 1-.008-.128 10.2 10.2 0 0 0 .372-.292.074.074 0 0 1 .077-.01c3.928 1.793 8.18 1.793 12.062 0a.074.074 0 0 1 .078.01c.12.098.246.198.373.292a.077.077 0 0 1-.006.127 12.299 12.299 0 0 1-1.873.892.077.077 0 0 0-.041.107c.36.698.772 1.362 1.225 1.993a.076.076 0 0 0 .084.028 19.839 19.839 0 0 0 6.002-3.03.077.077 0 0 0 .032-.054c.5-5.177-.838-9.674-3.549-13.66a.061.061 0 0 0-.031-.03z" />
    </svg>
  );
}

function TelegramIcon({ size = 22 }: { size?: number }) {
  return (
    <svg viewBox="0 0 24 24" width={size} height={size} fill="#fff">
      <path d="M11.944 0A12 12 0 0 0 0 12a12 12 0 0 0 12 12 12 12 0 0 0 12-12A12 12 0 0 0 12 0a12 12 0 0 0-.056 0zm4.962 7.224c.1-.002.321.023.465.14a.506.506 0 0 1 .171.325c.016.093.036.306.02.472-.18 1.898-.962 6.502-1.36 8.627-.168.9-.499 1.201-.82 1.23-.696.065-1.225-.46-1.9-.902-1.056-.693-1.653-1.124-2.678-1.8-1.185-.78-.417-1.21.258-1.91.177-.184 3.247-2.977 3.307-3.23.007-.032.014-.15-.056-.212s-.174-.041-.249-.024c-.106.024-1.793 1.14-5.061 3.345-.479.33-.913.49-1.302.48-.428-.008-1.252-.241-1.865-.44-.752-.245-1.349-.374-1.297-.789.027-.216.325-.437.893-.663 3.498-1.524 5.83-2.529 6.998-3.014 3.332-1.386 4.025-1.627 4.476-1.635z" />
    </svg>
  );
}

function MessengerIcon({ size = 22 }: { size?: number }) {
  return (
    <svg viewBox="0 0 24 24" width={size} height={size} fill="#fff">
      <path d="M.001 11.639C.001 4.949 5.241 0 12.001 0S24 4.95 24 11.639c0 6.689-5.24 11.638-12 11.638-1.21 0-2.38-.16-3.47-.46a.96.96 0 0 0-.64.05l-2.39 1.05a.96.96 0 0 1-1.35-.85l-.07-2.14a.97.97 0 0 0-.32-.68A11.39 11.389 0 0 1 .002 11.64zm8.32-2.19-4.03 6.41c-.6.96.54 2.01 1.46 1.34l3.86-2.93a.72.72 0 0 1 .85-.02l2.85 2.14a1.8 1.8 0 0 0 2.62-.58l4.03-6.41c.6-.96-.54-2.01-1.46-1.34l-3.86 2.93a.72.72 0 0 1-.85.02l-2.85-2.14a1.8 1.8 0 0 0-2.62.58z" />
    </svg>
  );
}

function WhatsAppIcon({ size = 22 }: { size?: number }) {
  return (
    <svg viewBox="0 0 24 24" width={size} height={size} fill="#fff">
      <path d="M17.472 14.382c-.297-.149-1.758-.867-2.03-.967-.273-.099-.471-.148-.67.15-.197.297-.767.966-.94 1.164-.173.199-.347.223-.644.075-.297-.15-1.255-.463-2.39-1.475-.883-.788-1.48-1.761-1.653-2.059-.173-.297-.018-.458.13-.606.134-.133.298-.347.446-.52.149-.174.198-.298.298-.497.099-.198.05-.371-.025-.52-.075-.149-.669-1.612-.916-2.207-.242-.579-.487-.5-.669-.51-.173-.008-.371-.01-.57-.01-.198 0-.52.074-.792.372-.272.297-1.04 1.016-1.04 2.479 0 1.462 1.065 2.875 1.213 3.074.149.198 2.096 3.2 5.077 4.487.709.306 1.262.489 1.694.625.712.227 1.36.195 1.871.118.571-.085 1.758-.719 2.006-1.413.248-.694.248-1.289.173-1.413-.074-.124-.272-.198-.57-.347m-5.421 7.403h-.004a9.87 9.87 0 01-5.031-1.378l-.361-.214-3.741.982.998-3.648-.235-.374a9.86 9.86 0 01-1.51-5.26c.001-5.45 4.436-9.884 9.888-9.884 2.64 0 5.122 1.03 6.988 2.898a9.825 9.825 0 012.893 6.994c-.003 5.45-4.437 9.884-9.885 9.884m8.413-18.297A11.815 11.815 0 0012.05 0C5.495 0 .16 5.335.157 11.892c0 2.096.547 4.142 1.588 5.945L.057 24l6.305-1.654a11.882 11.882 0 005.683 1.448h.005c6.554 0 11.89-5.335 11.893-11.893a11.821 11.821 0 00-3.48-8.413z" />
    </svg>
  );
}

function XIcon({ size = 22 }: { size?: number }) {
  return (
    <svg viewBox="0 0 24 24" width={size} height={size} fill="#fff">
      <path d="M18.244 2.25h3.308l-7.227 8.26 8.502 11.24H16.17l-5.214-6.817L4.99 21.75H1.68l7.73-8.835L1.254 2.25H8.08l4.713 6.231zm-1.161 17.52h1.833L7.084 4.126H5.117z" />
    </svg>
  );
}

function LinearIcon({ size = 22 }: { size?: number }) {
  return (
    <svg viewBox="0 0 24 24" width={size} height={size} fill="#fff">
      <path d="M2.997 11.573a9.108 9.108 0 0 1 1.953-4.56l7.036 7.037a9.108 9.108 0 0 1-4.559 1.952L2.997 11.573ZM3.781 5.903A9.108 9.108 0 0 1 11.999 2.4c5.014 0 9.1 4.086 9.1 9.1a9.108 9.108 0 0 1-3.503 8.218L3.781 5.903ZM2.687 12.782l8.531 8.531a9.175 9.175 0 0 1-1.218.082c-5.014 0-9.1-4.086-9.1-9.1 0-.413.028-.82.082-1.218l1.705 1.705Z" />
    </svg>
  );
}

function TwilioIcon({ size = 22 }: { size?: number }) {
  return (
    <svg viewBox="0 0 24 24" width={size} height={size} fill="#fff">
      <path d="M12 0C5.373 0 0 5.373 0 12s5.373 12 12 12 12-5.373 12-12S18.627 0 12 0zm0 20.4a8.4 8.4 0 1 1 0-16.8 8.4 8.4 0 0 1 0 16.8zm3.6-11.4a2.4 2.4 0 1 1-4.8 0 2.4 2.4 0 0 1 4.8 0zm0 6a2.4 2.4 0 1 1-4.8 0 2.4 2.4 0 0 1 4.8 0zm-6 0a2.4 2.4 0 1 1-4.8 0 2.4 2.4 0 0 1 4.8 0zm0-6a2.4 2.4 0 1 1-4.8 0 2.4 2.4 0 0 1 4.8 0z" />
    </svg>
  );
}

function RedisIcon({ size = 20 }: { size?: number }) {
  return (
    <svg viewBox="0 0 24 24" width={size} height={size} fill="#fff">
      <path d="M22.71 13.145c-1.66 2.092-3.452 4.483-7.038 4.483-3.203 0-4.397-2.825-4.48-5.12.701 1.484 2.073 2.685 4.214 2.63 4.117-.133 6.94-3.852 6.94-7.239 0-4.05-3.022-6.972-8.268-6.972-3.752 0-8.4 1.428-11.455 3.685C2.59 6.937 3.885 9.958 4.35 9.626c2.648-1.904 4.748-3.13 6.784-3.744C8.12 9.244.886 17.05 0 18.425c.1 1.261 1.66 4.648 2.424 4.648.232 0 .431-.133.664-.365a100.49 100.49 0 0 0 5.54-6.765c.222 3.104 1.748 6.898 6.014 6.898 3.819 0 7.604-2.756 9.33-8.965.2-.764-.73-1.361-1.261-.73zm-4.349-5.013c0 1.959-1.926 2.922-3.685 2.922-.941 0-1.664-.247-2.235-.568 1.051-1.592 2.092-3.225 3.21-4.973 1.972.334 2.71 1.43 2.71 2.619z" />
    </svg>
  );
}

function PostgresIcon({ size = 20 }: { size?: number }) {
  return (
    <svg viewBox="0 0 24 24" width={size} height={size} fill="#fff">
      <path d="M23.5594 14.7228a.5269.5269 0 0 0-.0563-.1191c-.139-.2632-.4768-.3418-1.0074-.2321-1.6533.3411-2.2935.1312-2.5256-.0191 1.342-2.0482 2.445-4.522 3.0411-6.8297.2714-1.0507.7982-3.5237.1222-4.7316a1.5641 1.5641 0 0 0-.1509-.235C21.6931.9086 19.8007.0248 17.5099.0005c-1.4947-.0158-2.7705.3461-3.1161.4794a9.449 9.449 0 0 0-.5159-.0816 8.044 8.044 0 0 0-1.3114-.1278c-1.1822-.0184-2.2038.2642-3.0498.8406-.8573-.3211-4.7888-1.645-7.2219.0788C.9359 2.1526.3086 3.8733.4302 6.3043c.0409.818.5069 3.334 1.2423 5.7436.4598 1.5065.9387 2.7019 1.4334 3.582.553.9942 1.1259 1.5933 1.7143 1.7895.4474.1491 1.1327.1441 1.8581-.7279.8012-.9635 1.5903-1.8258 1.9446-2.2069.4351.2355.9064.3625 1.39.3772a.0569.0569 0 0 0 .0004.0041 11.0312 11.0312 0 0 0-.2472.3054c-.3389.4302-.4094.5197-1.5002.7443-.3102.064-1.1344.2339-1.1464.8115-.0025.1224.0329.2309.0919.3268.2269.4231.9216.6097 1.015.6331 1.3345.3335 2.5044.092 3.3714-.6787-.017 2.231.0775 4.4174.3454 5.0874.2212.5529.7618 1.9045 2.4692 1.9043.2505 0 .5263-.0291.8296-.0941 1.7819-.3821 2.5557-1.1696 2.855-2.9059.1503-.8707.4016-2.8753.5388-4.1012.0169-.0703.0357-.1207.057-.1362.0007-.0005.0697-.0471.4272.0307a.3673.3673 0 0 0 .0443.0068l.2539.0223.0149.001c.8468.0384 1.9114-.1426 2.5312-.4308.6438-.2988 1.8057-1.0323 1.5951-1.6698z" />
    </svg>
  );
}

function MysqlIcon({ size = 20 }: { size?: number }) {
  return (
    <svg viewBox="0 0 24 24" width={size} height={size} fill="#fff">
      <path d="M16.405 5.501c-.115 0-.193.014-.274.033v.013h.014c.054.104.146.18.214.273.054.107.1.214.154.32l.014-.015c.094-.066.14-.172.14-.333-.04-.047-.046-.094-.08-.14-.04-.067-.126-.1-.18-.153zM5.77 18.695h-.927a50.854 50.854 0 00-.27-4.41h-.008l-1.41 4.41H2.45l-1.4-4.41h-.01a72.892 72.892 0 00-.195 4.41H0c.055-1.966.192-3.81.41-5.53h1.15l1.335 4.064h.008l1.347-4.064h1.095c.242 2.015.384 3.86.428 5.53zm4.017-4.08c-.378 2.045-.876 3.533-1.492 4.46-.482.716-1.01 1.073-1.583 1.073-.153 0-.34-.046-.566-.138v-.494c.11.017.24.026.386.026.268 0 .483-.075.647-.222.197-.18.295-.382.295-.605 0-.155-.077-.47-.23-.944L6.23 14.615h.91l.727 2.36c.164.536.233.91.205 1.123.4-1.064.678-2.227.835-3.483zm12.325 4.08h-2.63v-5.53h.885v4.85h1.745zm-3.32.135l-1.016-.5c.09-.076.177-.158.255-.25.433-.506.648-1.258.648-2.253 0-1.83-.718-2.746-2.155-2.746-.704 0-1.254.232-1.65.697-.43.508-.646 1.256-.646 2.245 0 .972.19 1.686.574 2.14.35.41.877.615 1.583.615.264 0 .506-.033.725-.098l1.325.772.36-.622zM15.5 17.588c-.225-.36-.337-.94-.337-1.736 0-1.393.424-2.09 1.27-2.09.443 0 .77.167.977.5.224.362.336.936.336 1.723 0 1.404-.424 2.108-1.27 2.108-.445 0-.77-.167-.978-.5zm-1.658-.425c0 .47-.172.856-.516 1.156-.344.3-.803.45-1.384.45-.543 0-1.064-.172-1.573-.515l.237-.476c.438.22.833.328 1.19.328.332 0 .593-.073.783-.22a.754.754 0 00.3-.615c0-.33-.23-.61-.648-.845-.388-.213-1.163-.657-1.163-.657-.422-.307-.632-.636-.632-1.177 0-.45.157-.81.47-1.085.315-.278.72-.415 1.22-.415.512 0 .98.136 1.4.41l-.213.476a2.726 2.726 0 00-1.064-.23c-.283 0-.502.068-.654.206a.685.685 0 00-.248.524c0 .328.234.61.666.85.393.215 1.187.67 1.187.67.433.305.648.63.648 1.168zm9.382-5.852c-.535-.014-.95.04-1.297.188-.1.04-.26.04-.274.167.055.053.063.14.11.214.08.134.218.313.346.407.14.11.28.216.427.31.26.16.555.255.81.416.145.094.293.213.44.313.073.05.12.14.214.172v-.02c-.046-.06-.06-.147-.105-.214-.067-.067-.134-.127-.2-.193a3.223 3.223 0 00-.695-.675c-.214-.146-.682-.35-.77-.595l-.013-.014c.146-.013.32-.066.46-.106.227-.06.435-.047.67-.106.106-.027.213-.06.32-.094v-.06c-.12-.12-.21-.283-.334-.395a8.867 8.867 0 00-1.104-.823c-.21-.134-.476-.22-.697-.334-.08-.04-.214-.06-.26-.127-.12-.146-.19-.34-.275-.514a17.69 17.69 0 01-.547-1.163c-.12-.262-.193-.523-.34-.763-.69-1.137-1.437-1.826-2.586-2.5-.247-.14-.543-.2-.856-.274-.167-.008-.334-.02-.5-.027-.11-.047-.216-.174-.31-.235-.38-.24-1.364-.76-1.644-.072-.18.434.267.862.422 1.082.115.153.26.328.34.5.047.116.06.235.107.356.106.294.207.622.347.897.073.14.153.287.247.413.054.073.146.107.167.227-.094.136-.1.334-.154.5-.24.757-.146 1.693.194 2.25.107.166.362.534.703.393.3-.12.234-.5.32-.835.02-.08.007-.133.048-.187v.015c.094.188.188.367.274.555.206.328.566.668.867.895.16.12.287.328.487.402v-.02h-.015c-.043-.058-.1-.086-.154-.133a3.445 3.445 0 01-.35-.4 8.76 8.76 0 01-.747-1.218c-.11-.21-.202-.436-.29-.643-.04-.08-.04-.2-.107-.24-.1.146-.247.273-.32.453-.127.288-.14.642-.188 1.01-.027.007-.014 0-.027.014-.214-.052-.287-.274-.367-.46-.2-.475-.233-1.238-.06-1.785.047-.14.247-.582.167-.716-.042-.127-.174-.2-.247-.303a2.478 2.478 0 01-.24-.427c-.16-.374-.24-.788-.414-1.162-.08-.173-.22-.354-.334-.513-.127-.18-.267-.307-.368-.52-.033-.073-.08-.194-.027-.274.014-.054.042-.075.094-.09.088-.072.335.022.422.062.247.1.455.194.662.334.094.066.195.193.315.226h.14c.214.047.455.014.655.073.355.114.675.28.962.46a5.953 5.953 0 012.085 2.286c.08.154.115.295.188.455.14.33.313.663.455.982.14.315.275.636.476.897.1.14.502.213.682.286.133.06.34.115.46.188.23.14.454.3.67.454.11.076.443.243.463.378z" />
    </svg>
  );
}

function MemoryIcon({ size = 20 }: { size?: number }) {
  return (
    <svg viewBox="0 0 24 24" width={size} height={size} fill="none" stroke="#fff" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
      <path d="M6 19v-3m4 3v-3m4 3v-3m4 3v-3" />
      <rect x="2" y="6" width="20" height="10" rx="2" />
      <path d="M6 10h0m4 0h0m4 0h0m4 0h0" />
    </svg>
  );
}

const adapters: Adapter[] = [
  {
    name: 'Slack',
    slug: 'slack',
    gem: 'chat_sdk-slack',
    type: 'platform',
    tagline: 'Build bots for Slack workspaces with threads, reactions, modals, streaming, and Block Kit cards.',
    color: '#4A154B',
    icon: <SlackIcon />,
    official: true,
    features: {
      post: 'yes', edit: 'yes', delete: 'yes', ephemeral: 'yes',
      reactions: 'yes', files: 'yes', modals: 'yes', streaming: 'yes',
      dms: 'yes', history: 'yes', typing: 'yes',
    },
  },
  {
    name: 'Microsoft Teams',
    slug: 'teams',
    gem: 'chat_sdk-teams',
    type: 'platform',
    tagline: 'Deploy bots to Microsoft Teams with Adaptive Cards, mentions, reactions, and file sharing.',
    color: '#6264A7',
    icon: <TeamsIcon />,
    official: true,
    features: {
      post: 'yes', edit: 'yes', delete: 'yes', ephemeral: 'no',
      reactions: 'partial', files: 'yes', modals: 'no', streaming: 'yes',
      dms: 'yes', history: 'yes', typing: 'yes',
    },
  },
  {
    name: 'Google Chat',
    slug: 'gchat',
    gem: 'chat_sdk-gchat',
    type: 'platform',
    tagline: 'Integrate with Google Chat spaces for team collaboration with Card V2 and ephemeral messages.',
    color: '#00AC47',
    icon: <GChatIcon />,
    official: true,
    features: {
      post: 'yes', edit: 'yes', delete: 'yes', ephemeral: 'yes',
      reactions: 'yes', files: 'no', modals: 'no', streaming: 'yes',
      dms: 'yes', history: 'yes', typing: 'no',
    },
  },
  {
    name: 'Mattermost',
    slug: 'mattermost',
    gem: 'chat_sdk-mattermost',
    type: 'platform',
    tagline: 'Connect to Mattermost servers with message attachments, reactions, typing indicators, and file uploads.',
    color: '#0058CC',
    icon: <MattermostIcon />,
    official: true,
    features: {
      post: 'yes', edit: 'yes', delete: 'yes', ephemeral: 'yes',
      reactions: 'yes', files: 'yes', modals: 'no', streaming: 'yes',
      dms: 'yes', history: 'yes', typing: 'yes',
    },
  },
  {
    name: 'Discord',
    slug: 'discord',
    gem: 'chat_sdk-discord',
    type: 'platform',
    tagline: 'Create Discord bots with slash commands, rich embeds, interactive buttons, and file attachments.',
    color: '#5865F2',
    icon: <DiscordIcon />,
    official: true,
    features: {
      post: 'yes', edit: 'yes', delete: 'yes', ephemeral: 'no',
      reactions: 'yes', files: 'yes', modals: 'no', streaming: 'yes',
      dms: 'yes', history: 'yes', typing: 'yes',
    },
  },
  {
    name: 'Telegram',
    slug: 'telegram',
    gem: 'chat_sdk-telegram',
    type: 'platform',
    tagline: 'Build Telegram bots with inline keyboards, reactions, typing indicators, and media support.',
    color: '#26A5E4',
    icon: <TelegramIcon />,
    official: true,
    features: {
      post: 'yes', edit: 'yes', delete: 'yes', ephemeral: 'no',
      reactions: 'yes', files: 'yes', modals: 'no', streaming: 'yes',
      dms: 'yes', history: 'no', typing: 'yes',
    },
  },
  {
    name: 'Twilio',
    slug: 'twilio',
    gem: 'chat_sdk-twilio',
    type: 'platform',
    tagline: 'Send and receive SMS/MMS messages through Twilio with webhook signature verification.',
    color: '#F22F46',
    icon: <TwilioIcon />,
    official: true,
    features: {
      post: 'yes', edit: 'no', delete: 'no', ephemeral: 'no',
      reactions: 'no', files: 'no', modals: 'no', streaming: 'no',
      dms: 'yes', history: 'no', typing: 'no',
    },
  },
  {
    name: 'Messenger',
    slug: 'messenger',
    gem: 'chat_sdk-messenger',
    type: 'platform',
    tagline: 'Build Facebook Messenger bots with HMAC-SHA256 verification, Generic/Button templates, and typing indicators.',
    color: '#0084FF',
    icon: <MessengerIcon />,
    official: true,
    features: {
      post: 'yes', edit: 'no', delete: 'no', ephemeral: 'no',
      reactions: 'no', files: 'yes', modals: 'no', streaming: 'no',
      dms: 'yes', history: 'no', typing: 'yes',
    },
  },
  {
    name: 'WhatsApp',
    slug: 'whatsapp',
    gem: 'chat_sdk-whatsapp',
    type: 'platform',
    tagline: 'Integrate with WhatsApp Business Cloud API with interactive button messages, emoji reactions, and media uploads.',
    color: '#25D366',
    icon: <WhatsAppIcon />,
    official: true,
    features: {
      post: 'yes', edit: 'no', delete: 'no', ephemeral: 'no',
      reactions: 'yes', files: 'yes', modals: 'no', streaming: 'no',
      dms: 'yes', history: 'no', typing: 'no',
    },
  },
  {
    name: 'X',
    slug: 'x',
    gem: 'chat_sdk-x',
    type: 'platform',
    tagline: 'Build X (Twitter) bots with tweets, direct messages, HMAC-SHA256 webhook verification, and likes.',
    color: '#000000',
    icon: <XIcon />,
    official: true,
    features: {
      post: 'yes', edit: 'no', delete: 'yes', ephemeral: 'no',
      reactions: 'yes', files: 'no', modals: 'no', streaming: 'no',
      dms: 'yes', history: 'yes', typing: 'no',
    },
  },
  {
    name: 'Linear',
    slug: 'linear',
    gem: 'chat_sdk-linear',
    type: 'platform',
    tagline: 'Integrate with Linear issue comments via GraphQL with HMAC-SHA256 webhook verification and emoji reactions.',
    color: '#5E6AD2',
    icon: <LinearIcon />,
    official: true,
    features: {
      post: 'yes', edit: 'yes', delete: 'yes', ephemeral: 'no',
      reactions: 'yes', files: 'no', modals: 'no', streaming: 'yes',
      dms: 'no', history: 'yes', typing: 'no',
    },
  },
  {
    name: 'Redis',
    slug: 'state-redis',
    gem: 'chat_sdk-state-redis',
    type: 'state',
    tagline: 'High-performance state backend with atomic Lua-guarded locks and TTL-based key expiration.',
    color: '#DC382D',
    icon: <RedisIcon />,
    official: true,
    features: {},
  },
  {
    name: 'PostgreSQL',
    slug: 'state-pg',
    gem: 'chat_sdk-state-pg',
    type: 'state',
    tagline: 'PostgreSQL state backend with auto-migration, JSONB storage, and row-level locking.',
    color: '#336791',
    icon: <PostgresIcon />,
    official: true,
    features: {},
  },
  {
    name: 'MySQL',
    slug: 'state-mysql',
    gem: 'chat_sdk-state-mysql',
    type: 'state',
    tagline: 'MySQL state backend with auto-migration, JSON storage, and InnoDB row-level locking.',
    color: '#00758F',
    icon: <MysqlIcon />,
    official: true,
    features: {},
  },
  {
    name: 'Memory',
    slug: 'state-memory',
    gem: 'chat_sdk (built-in)',
    type: 'state',
    tagline: 'Zero-dependency in-process state for development, testing, and single-process deployments.',
    color: '#6B7280',
    icon: <MemoryIcon />,
    official: true,
    features: {},
  },
];

const featureLabels: Record<string, string> = {
  post: 'Post', edit: 'Edit', delete: 'Delete', ephemeral: 'Ephemeral',
  reactions: 'Reactions', files: 'Files', modals: 'Modals', streaming: 'Streaming',
  dms: 'DMs', history: 'History', typing: 'Typing',
};

function FeatureBadge({ status }: { status: Feature }) {
  if (status === 'yes') return <span className="text-green-600 dark:text-green-400 font-bold">&#10003;</span>;
  if (status === 'partial') return <span className="text-yellow-600 dark:text-yellow-400 font-bold">~</span>;
  return <span className="text-gray-300 dark:text-gray-600">&#10005;</span>;
}

function AdapterCard({ adapter }: { adapter: Adapter }) {
  return (
    <Link
      href={`/docs/adapters/${adapter.slug}`}
      className="group flex flex-col p-5 rounded-2xl border border-gray-200 dark:border-gray-800 hover:border-red-500/30 dark:hover:border-red-500/30 transition-all hover:shadow-md bg-white dark:bg-gray-950"
    >
      <div className="flex items-center justify-between mb-4">
        <div className="flex items-center gap-3">
          <div className="w-10 h-10 rounded-xl flex items-center justify-center" style={{ backgroundColor: adapter.color }}>
            {adapter.icon}
          </div>
          <h3 className="font-semibold text-lg group-hover:text-red-600 dark:group-hover:text-red-400 transition-colors">
            {adapter.name}
          </h3>
        </div>
        {adapter.official && (
          <span className="text-[10px] font-semibold uppercase tracking-wider px-1.5 py-0.5 rounded bg-red-500/10 text-red-600 dark:text-red-400 border border-red-500/20">
            Official
          </span>
        )}
      </div>
      <p className="text-sm text-gray-500 dark:text-gray-400 mb-4 flex-1">{adapter.tagline}</p>
      <div className="pt-3 border-t border-gray-100 dark:border-gray-800">
        <code className="text-xs text-gray-400">{adapter.gem}</code>
      </div>
    </Link>
  );
}

function BuildYourOwnCard({ emoji, text, href }: { emoji: string; text: string; href: string }) {
  return (
    <Link
      href={href}
      className="group flex flex-col items-center justify-center p-5 rounded-2xl border border-dashed border-gray-300 dark:border-gray-700 hover:border-red-500/30 transition-all text-center"
    >
      <span className="text-2xl mb-2">{emoji}</span>
      <h3 className="font-semibold mb-1 group-hover:text-red-600 dark:group-hover:text-red-400 transition-colors">Build your own</h3>
      <p className="text-xs text-gray-500 dark:text-gray-400">{text}</p>
    </Link>
  );
}

type FilterTab = 'all' | 'platform' | 'state';

export default function AdaptersPage() {
  const [tab, setTab] = useState<FilterTab>('all');
  const [search, setSearch] = useState('');
  const platformAdapters = adapters.filter((a) => a.type === 'platform');

  const filtered = adapters.filter((a) => {
    if (tab !== 'all' && a.type !== tab) return false;
    if (search && !a.name.toLowerCase().includes(search.toLowerCase()) && !a.gem.toLowerCase().includes(search.toLowerCase())) return false;
    return true;
  });
  const fp = filtered.filter((a) => a.type === 'platform');
  const fs = filtered.filter((a) => a.type === 'state');

  return (
    <main className="max-w-5xl mx-auto px-6 py-16">
      <h1 className="text-4xl font-bold mb-3">Adapters</h1>
      <p className="text-lg text-gray-500 dark:text-gray-400 mb-8">
        Published under <code className="text-xs">chat_sdk-*</code> and maintained by Rootly.
      </p>

      {/* Filter bar */}
      <div className="flex flex-col sm:flex-row gap-4 mb-8">
        <div className="flex rounded-lg border border-gray-200 dark:border-gray-800 overflow-hidden">
          {(['all', 'platform', 'state'] as const).map((t) => (
            <button
              key={t}
              onClick={() => setTab(t)}
              className={`px-5 py-2 text-sm font-medium transition-colors ${
                tab === t
                  ? 'bg-white dark:bg-gray-900 text-gray-900 dark:text-white'
                  : 'text-gray-500 dark:text-gray-400 hover:text-gray-700 dark:hover:text-gray-300'
              }`}
            >
              {t === 'all' ? 'All' : t === 'platform' ? 'Platform' : 'State'}
            </button>
          ))}
        </div>
        <div className="flex-1">
          <input
            type="text"
            placeholder="Search adapters..."
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            className="w-full px-4 py-2 text-sm rounded-lg border border-gray-200 dark:border-gray-800 bg-white dark:bg-gray-950 text-gray-900 dark:text-white placeholder-gray-400 focus:outline-none focus:border-red-500/50"
          />
        </div>
      </div>

      {fp.length > 0 && (
        <>
          <h2 className="text-2xl font-bold mb-6">Platform Adapters</h2>
          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4 mb-12">
            {fp.map((a) => <AdapterCard key={a.slug} adapter={a} />)}
            {!search && <BuildYourOwnCard emoji="🔌" text="Extend ChatSDK with shared contract specs and the adapter base class." href="/docs/contributing/building-adapters" />}
          </div>
        </>
      )}

      {fs.length > 0 && (
        <>
          <h2 className="text-2xl font-bold mb-6">State Backends</h2>
          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4 mb-12">
            {fs.map((a) => <AdapterCard key={a.slug} adapter={a} />)}
            {!search && <BuildYourOwnCard emoji="🗄️" text="Implement the State::Base interface with shared contract specs." href="/docs/contributing/building-state-adapters" />}
          </div>
        </>
      )}

      {filtered.length === 0 && (
        <p className="text-center text-gray-500 dark:text-gray-400 py-12">No adapters match your search.</p>
      )}

      {/* Feature matrix */}
      <h2 className="text-2xl font-bold mb-6">Feature Matrix</h2>
      <div className="overflow-x-auto mb-16 rounded-xl border border-gray-200 dark:border-gray-800">
        <table className="w-full text-sm">
          <thead>
            <tr className="bg-gray-50 dark:bg-gray-900">
              <th className="text-left py-3.5 pl-5 pr-4 font-semibold">Feature</th>
              {platformAdapters.map((a) => (
                <th key={a.slug} className="text-center py-3.5 px-4 font-semibold">
                  <div className="flex items-center justify-center gap-2">
                    <span className="w-4 h-4 rounded" style={{ backgroundColor: a.color }} />
                    <span>{a.name}</span>
                  </div>
                </th>
              ))}
            </tr>
          </thead>
          <tbody>
            {Object.entries(featureLabels).map(([key, label], i) => (
              <tr key={key} className={i % 2 === 0 ? 'bg-white dark:bg-gray-950' : 'bg-gray-50/50 dark:bg-gray-900/50'}>
                <td className="py-3 pl-5 pr-4 text-gray-600 dark:text-gray-400">{label}</td>
                {platformAdapters.map((a) => (
                  <td key={a.slug} className="text-center py-3 px-4">
                    <FeatureBadge status={a.features[key] || 'no'} />
                  </td>
                ))}
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </main>
  );
}
